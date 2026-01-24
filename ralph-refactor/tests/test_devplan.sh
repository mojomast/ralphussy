#!/usr/bin/env bash

__TEST_DIR__="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$__TEST_DIR__/../lib/devplan.sh"

TEST_TMP_DIR="/tmp/test_devplan_$(date +%s)"
mkdir -p "$TEST_TMP_DIR"

test_plain_list_items() {
    echo "Testing plain '- task' list items..."
    printf '%s
'- task A
'- task B
'- task C
'" > "$TEST_TMP_DIR/plain.md"

    if has_pending_tasks "$TEST_TMP_DIR/plain.md"; then
        echo "✅ plain list detected as pending"
        return 0
    else
        echo "❌ plain list not detected"
        return 1
    fi
}

test_checklist_items() {
    echo "Testing checklist '- [ ] task' items..."
    printf '%s
'- [ ] check A
'- [ ] check B
'" > "$TEST_TMP_DIR/checklist.md"

    if has_pending_tasks "$TEST_TMP_DIR/checklist.md"; then
        echo "✅ checklist detected as pending"
        return 0
    else
        echo "❌ checklist not detected"
        return 1
    fi
}

test_yaml_frontmatter() {
    echo "Testing YAML frontmatter stripping..."
    cat > "$TEST_TMP_DIR/frontmatter.md" <<'EOF'
---
title: example
---

- task from frontmatter
- [ ] after frontmatter
EOF

    if has_pending_tasks "$TEST_TMP_DIR/frontmatter.md"; then
        echo "✅ frontmatter devplan detected pending tasks"
        return 0
    else
        echo "❌ frontmatter parsing failed"
        return 1
    fi
}

test_html_comments_and_whitespace() {
    echo "Testing HTML comments and extra whitespace..."
    cat > "$TEST_TMP_DIR/comments.md" <<'EOF'
<!-- this is a comment -->

  -   [ ]    spaced task   <!-- inline comment -->

EOF

    if has_pending_tasks "$TEST_TMP_DIR/comments.md"; then
        echo "✅ comments and whitespace handled"
        return 0
    else
        echo "❌ comments/whitespace not handled"
        return 1
    fi
}

run_all_tests() {
    local failures=0
    test_plain_list_items || failures=$((failures+1))
    test_checklist_items || failures=$((failures+1))
    test_yaml_frontmatter || failures=$((failures+1))
    test_html_comments_and_whitespace || failures=$((failures+1))

    echo "\nDevplan tests completed: $failures failed"
    return $failures
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_all_tests
fi
