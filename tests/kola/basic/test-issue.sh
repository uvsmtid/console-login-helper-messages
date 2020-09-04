#!/bin/bash     

# Test for issuegen's basic functionality

set -xeuo pipefail

. ${KOLA_EXT_DATA}/test-util.sh

# Pretend to be running from a TTY
faketty () {
    outfile=$1
    shift 1
    script -c "$(printf "%q " "$@")" "${outfile}"
}

for unit in issuegen.path gensnippet-ssh-keys.service; do
  if ! systemctl is-enabled ${PKG_NAME}-${unit}; then
    fatal "unit ${unit} not enabled"
  fi
done
ok "systemd units enabled"

cd $(mktemp -d)

# If using private runtime directory, check that the issue symlink was created.
# `issuegen` generates an issue at runtime, and places the generated file in 
# /run/issue.d/. To have agetty display this, a symlink from /etc/issue.d/ to 
# /run/issue.d/ is needed.
if [ ${USE_PUBLIC_RUN_DIR} == "false" ]; then
    ls -l /etc/issue.d/40_${PKG_NAME}.issue > symlink.txt
    assert_file_has_content symlink.txt '->'
    assert_file_has_content symlink.txt '/run/console-login-helper-messages/40_console-login-helper-messages.issue'
    ok "symlink"
fi

# If SSH keys are present, check that SSH keys snippets were generated by 
# `gensnippet_ssh_keys` and shown by `agetty`.
if test -n "$(find /etc/ssh -name 'ssh_host_*_key' -print -quit)"; then
    sleep 2
    faketty agetty_output.txt agetty --show-issue
    assert_file_has_content agetty_output.txt 'SSH host key:*'
    ok "gensnippet_ssh_keys"
fi

# Check that a new issue snippet is generated when a .issue file is dropped into 
# the issue run directory.
echo 'foo' > ${ISSUE_RUN_SNIPPETS_PATH}/10_foo.issue
sleep 2
faketty agetty_output.txt agetty --show-issue
assert_file_has_content agetty_output.txt 'foo'
ok "display new single issue snippet"

# Check that a large burst of .issue files dropped into the issue run directory
# will all get displayed, and that we don't hit any systemd 'start-limit-hit' 
# failures
for i in {1..150};
do
    echo "Issue snippet: $i" > ${ISSUE_RUN_SNIPPETS_PATH}/${i}_spam.issue
done
sleep 2
faketty agetty_output.txt agetty --show-issue
for i in {1..150};
do
    assert_file_has_content agetty_output.txt "Issue snippet: $i"
done
systemctl status ${PKG_NAME}-issuegen.path > issuegen_status.txt
assert_not_file_has_content issuegen_status.txt "unit-start-limit-hit"
ok "display burst of new issue snippets"

tap_finish
