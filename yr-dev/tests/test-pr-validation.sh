#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/../scripts/yr-dev-common.sh"

pass=0
fail=0
expect_pass() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else echo "FAIL expected pass: $n" >&2; fail=$((fail+1)); fi; }
expect_fail() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "FAIL expected rejection: $n" >&2; fail=$((fail+1)); else pass=$((pass+1)); fi; }

good_body=$'/kind feat\n\nFixes #\n\n接口变化：无外部接口变化。\n\n测试与验证：targeted tests PASS。\n\n- [x] 自检完成'

expect_pass "parenthesized title" validate_yr_subject "feat(function_proxy): add frontend service"
expect_pass "bracketed title" validate_yr_subject "fix[datasystem]: repair object lookup"
expect_fail "missing type" validate_yr_subject "Add frontend service"
expect_fail "missing description" validate_yr_subject "feat(frontend):"
expect_pass "single CLA signoff" validate_yr_commit_message $'feat(frontend): add route\n\nSigned-off-by: luozhancheng <luozhancheng@huawei.com>'
expect_fail "missing signoff" validate_yr_commit_message "feat(frontend): add route"
expect_fail "co-author" validate_yr_commit_message $'feat(frontend): add route\n\nSigned-off-by: luozhancheng <luozhancheng@huawei.com>\nCo-authored-by: Bot <bot@example.com>'
expect_pass "complete MR body" validate_yr_mr_body "openeuler/yuanrong-functionsystem" "feat(function_proxy): add frontend service" "$good_body"
expect_fail "kind mismatch" validate_yr_mr_body "openeuler/yuanrong-functionsystem" "fix(function_proxy): repair frontend service" "$good_body"
expect_fail "missing checklist" validate_yr_mr_body "openeuler/yuanrong-functionsystem" "feat(function_proxy): add frontend service" $'/kind feat\nFixes #\n接口变化：无。\n测试：PASS。'

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
