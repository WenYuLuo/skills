#!/usr/bin/env python3
"""Read-only Huawei Cloud CCE and ECS inventory for YuanRong cluster selection."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from huaweicloudsdkcore.auth.credentials import BasicCredentials, GlobalCredentials
from huaweicloudsdkcce.v3 import CceClient
from huaweicloudsdkcce.v3 import model as cce_model
from huaweicloudsdkecs.v2 import EcsClient
from huaweicloudsdkecs.v2 import model as ecs_model
from huaweicloudsdkiam.v3 import IamClient
from huaweicloudsdkiam.v3 import model as iam_model


KNOWN_REGIONS = ("cn-east-3", "cn-north-4", "cn-southwest-2")


def recursively_plain(value: Any) -> Any:
    if hasattr(value, "to_dict"):
        return recursively_plain(value.to_dict())
    if isinstance(value, list):
        return [recursively_plain(item) for item in value]
    if isinstance(value, dict):
        return {key: recursively_plain(item) for key, item in value.items()}
    return value


def parse_credentials_file(path: Path) -> dict[str, str]:
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        raise ValueError(f"credentials file must be mode 0600: {path} is {mode:04o}")
    values: dict[str, str] = {}
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"invalid credentials line {line_number} in {path}")
        key, value = line.split("=", 1)
        key = key.strip()
        if key not in {"HW_AK", "HW_SK"}:
            raise ValueError(f"unsupported key {key!r} in {path}")
        values[key] = value.strip().strip("'\"")
    return values


def load_credentials(explicit_path: str | None) -> tuple[str, str]:
    ak = os.environ.get("HW_AK", "")
    sk = os.environ.get("HW_SK", "")
    if ak and sk:
        return ak, sk
    configured = explicit_path or os.environ.get("HW_CREDENTIALS_FILE")
    path = Path(configured).expanduser() if configured else Path.home() / ".config/huawei-cloud/yr.env"
    if path.is_file():
        values = parse_credentials_file(path)
        ak = ak or values.get("HW_AK", "")
        sk = sk or values.get("HW_SK", "")
    if not ak or not sk:
        raise ValueError(
            "set HW_AK/HW_SK or create a mode-0600 credentials file at "
            "~/.config/huawei-cloud/yr.env"
        )
    return ak, sk


def discover_projects(ak: str, sk: str) -> tuple[str | None, list[dict[str, Any]]]:
    client = (
        IamClient.new_builder()
        .with_credentials(GlobalCredentials(ak, sk))
        .with_endpoint("https://iam.myhuaweicloud.com")
        .build()
    )
    domains = client.keystone_list_auth_domains(iam_model.KeystoneListAuthDomainsRequest())
    projects = client.keystone_list_auth_projects(iam_model.KeystoneListAuthProjectsRequest())
    domain_items = recursively_plain(getattr(domains, "domains", []) or [])
    project_items = recursively_plain(getattr(projects, "projects", []) or [])
    domain = domain_items[0].get("name") if domain_items else None
    return domain, [item for item in project_items if item.get("enabled") and item.get("name") != "MOS"]


def error_text(exc: Exception) -> str:
    text = " ".join(str(exc).split())
    return f"{type(exc).__name__}: {text[:500]}"


def cluster_summary(client: CceClient, cluster: Any, autopilot: bool = False) -> dict[str, Any]:
    raw = recursively_plain(cluster)
    metadata = raw.get("metadata") or {}
    status = raw.get("status") or {}
    spec = raw.get("spec") or {}
    cluster_id = metadata.get("uid")
    result: dict[str, Any] = {
        "name": metadata.get("name"),
        "id": cluster_id,
        "autopilot": autopilot,
        "phase": status.get("phase"),
        "version": spec.get("version"),
        "type": spec.get("type"),
        "flavor": spec.get("flavor"),
        "created_at": metadata.get("creation_timestamp"),
        "nodes": [],
        "node_pools": [],
        "warnings": [],
    }
    if not cluster_id or autopilot:
        return result
    try:
        response = client.list_nodes(cce_model.ListNodesRequest(cluster_id=cluster_id, limit=200))
        for node in recursively_plain(getattr(response, "items", []) or []):
            node_metadata = node.get("metadata") or {}
            node_status = node.get("status") or {}
            node_spec = node.get("spec") or {}
            result["nodes"].append(
                {
                    "name": node_metadata.get("name"),
                    "phase": node_status.get("phase"),
                    "private_ip": node_status.get("private_ip"),
                    "public_ip": node_status.get("public_ip"),
                    "flavor": node_spec.get("flavor"),
                    "last_probe_time": node_status.get("last_probe_time"),
                }
            )
    except Exception as exc:  # SDK exceptions vary by endpoint.
        result["nodes_error"] = error_text(exc)
    try:
        response = client.list_node_pools(
            cce_model.ListNodePoolsRequest(cluster_id=cluster_id, show_default_node_pool=True)
        )
        for pool in recursively_plain(getattr(response, "items", []) or []):
            pool_metadata = pool.get("metadata") or {}
            pool_status = pool.get("status") or {}
            pool_spec = pool.get("spec") or {}
            template = pool_spec.get("node_template") or {}
            pool_item = {
                "name": pool_metadata.get("name"),
                "current": pool_status.get("current_node"),
                "active": pool_status.get("active_node"),
                "creating": pool_status.get("creating_node"),
                "deleting": pool_status.get("deleting_node"),
                "flavor": template.get("flavor"),
                "autoscaling": pool_spec.get("autoscaling"),
            }
            result["node_pools"].append(pool_item)
            for condition in pool_status.get("conditions") or []:
                if condition.get("status") == "True" and condition.get("type") not in {"Scalable"}:
                    result["warnings"].append(
                        {"pool": pool_item["name"], "type": condition.get("type"), "message": condition.get("message")}
                    )
    except Exception as exc:
        result["node_pools_error"] = error_text(exc)
    return result


def list_cce(credential: BasicCredentials, region: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, str]]:
    client = (
        CceClient.new_builder()
        .with_credentials(credential)
        .with_endpoint(f"https://cce.{region}.myhuaweicloud.com")
        .build()
    )
    errors: dict[str, str] = {}
    response = client.list_clusters(cce_model.ListClustersRequest(detail="true"))
    clusters = [cluster_summary(client, item) for item in (getattr(response, "items", []) or [])]
    autopilot: list[dict[str, Any]] = []
    try:
        response = client.list_autopilot_clusters(cce_model.ListAutopilotClustersRequest(detail="true"))
        autopilot = [cluster_summary(client, item, True) for item in (getattr(response, "items", []) or [])]
    except Exception as exc:
        message = error_text(exc)
        if "status_code:404" not in message and "APIGW.0101" not in message:
            errors["autopilot"] = message
    return clusters, autopilot, errors


def list_ecs(credential: BasicCredentials, region: str) -> list[dict[str, Any]]:
    client = (
        EcsClient.new_builder()
        .with_credentials(credential)
        .with_endpoint(f"https://ecs.{region}.myhuaweicloud.com")
        .build()
    )
    servers: list[dict[str, Any]] = []
    offset = 0
    while True:
        response = client.list_servers_details(ecs_model.ListServersDetailsRequest(limit=1000, offset=offset))
        batch = recursively_plain(getattr(response, "servers", []) or [])
        for server in batch:
            addresses = []
            for values in (server.get("addresses") or {}).values():
                addresses.extend(item.get("addr") for item in values if item.get("addr"))
            servers.append(
                {
                    "name": server.get("name"),
                    "id": server.get("id"),
                    "status": server.get("status"),
                    "flavor": (server.get("flavor") or {}).get("id"),
                    "addresses": addresses,
                    "created_at": server.get("created"),
                }
            )
        if len(batch) < 1000:
            break
        offset += len(batch)
    return servers


def inventory_region(ak: str, sk: str, project: dict[str, Any], include_ecs: bool) -> dict[str, Any]:
    region = project["name"]
    credential = BasicCredentials(ak, sk, project["id"])
    result: dict[str, Any] = {"region": region, "cce": [], "autopilot": [], "ecs": [], "errors": {}}
    try:
        result["cce"], result["autopilot"], cce_errors = list_cce(credential, region)
        result["errors"].update(cce_errors)
    except Exception as exc:
        result["errors"]["cce"] = error_text(exc)
    if include_ecs:
        try:
            result["ecs"] = list_ecs(credential, region)
        except Exception as exc:
            result["errors"]["ecs"] = error_text(exc)
    return result


def selected_projects(projects: list[dict[str, Any]], requested: list[str]) -> list[dict[str, Any]]:
    by_name = {project["name"]: project for project in projects}
    if not requested:
        return list(by_name.values())
    missing = [region for region in requested if region not in by_name]
    if missing:
        raise ValueError(f"credential cannot access IAM project(s): {', '.join(missing)}")
    return [by_name[region] for region in dict.fromkeys(requested)]


def aggregate(document: dict[str, Any]) -> dict[str, Any]:
    clusters = [cluster for region in document["regions"] for cluster in region["cce"] + region["autopilot"]]
    nodes = [node for cluster in clusters for node in cluster["nodes"]]
    servers = [server for region in document["regions"] for server in region["ecs"]]
    return {
        "cce_clusters": len(clusters),
        "cce_cluster_phases": dict(Counter(cluster.get("phase") for cluster in clusters)),
        "cce_nodes": len(nodes),
        "cce_node_phases": dict(Counter(node.get("phase") for node in nodes)),
        "ecs_servers": len(servers),
        "ecs_statuses": dict(Counter(server.get("status") for server in servers)),
        "regions_with_resources": [
            region["region"] for region in document["regions"] if region["cce"] or region["autopilot"] or region["ecs"]
        ],
    }


def print_human(document: dict[str, Any], details: bool, name_pattern: str | None) -> None:
    summary = document["summary"]
    print(f"Account: {document.get('domain') or 'unknown'}")
    print(f"Queried: {document['queried_at']}")
    print(
        f"CCE: {summary['cce_clusters']} clusters; {summary['cce_nodes']} nodes "
        f"{summary['cce_node_phases']}"
    )
    print(f"ECS: {summary['ecs_servers']} servers {summary['ecs_statuses']} (includes CCE worker VMs)")
    matcher = re.compile(name_pattern) if name_pattern else None
    for region in document["regions"]:
        if not (region["cce"] or region["autopilot"] or region["ecs"] or region["errors"]):
            continue
        print(f"\n[{region['region']}]")
        for cluster in region["cce"] + region["autopilot"]:
            active = sum(node.get("phase") == "Active" for node in cluster["nodes"])
            print(
                f"CCE {cluster['name']}: phase={cluster['phase']} version={cluster['version']} "
                f"nodes={active}/{len(cluster['nodes'])} Active"
            )
            for warning in cluster["warnings"]:
                print(f"  WARNING pool={warning['pool']} type={warning['type']}")
        if region["ecs"]:
            counts = dict(Counter(server.get("status") for server in region["ecs"]))
            print(f"ECS: {len(region['ecs'])} {counts}")
            if details:
                for server in region["ecs"]:
                    if matcher and not matcher.search(server.get("name") or ""):
                        continue
                    print(
                        f"  {server['name']}: {server['status']} flavor={server['flavor']} "
                        f"addresses={','.join(server['addresses']) or '-'}"
                    )
        for service, message in region["errors"].items():
            print(f"UNVERIFIED {service}: {message}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", action="append", default=[], help="region to query; repeatable")
    parser.add_argument("--known-regions", action="store_true", help="query the catalog's three known regions")
    parser.add_argument("--credentials-file", help="mode-0600 file containing HW_AK and HW_SK")
    parser.add_argument("--no-ecs", action="store_true", help="skip ECS inventory")
    parser.add_argument("--details", action="store_true", help="show ECS names, flavors, and addresses")
    parser.add_argument("--name", help="only show detailed ECS rows whose name matches this regex")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--workers", type=int, default=6, help="parallel region queries; default 6")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        ak, sk = load_credentials(args.credentials_file)
        domain, projects = discover_projects(ak, sk)
        requested = list(args.region)
        if args.known_regions:
            requested.extend(KNOWN_REGIONS)
        projects = selected_projects(projects, requested)
    except Exception as exc:
        print(f"ERROR: {error_text(exc)}", file=sys.stderr)
        return 2

    regions: list[dict[str, Any]] = []
    workers = max(1, min(args.workers, len(projects) or 1))
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(inventory_region, ak, sk, project, not args.no_ecs) for project in projects]
        for future in as_completed(futures):
            regions.append(future.result())
    regions.sort(key=lambda item: item["region"])
    document = {
        "queried_at": datetime.now(timezone.utc).isoformat(),
        "domain": domain,
        "regions": regions,
    }
    document["summary"] = aggregate(document)
    if args.json:
        print(json.dumps(document, ensure_ascii=False, indent=2))
    else:
        print_human(document, args.details, args.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
