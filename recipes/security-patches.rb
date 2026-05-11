# Mitigate CVE-2026-43284 and CVE-2026-43500 (Dirty Frag)
# https://ubuntu.com/blog/dirty-frag-linux-vulnerability-fixes-available
# Blocks esp4, esp6, and rxrpc kernel modules until a patched kernel is deployed.
file '/etc/modprobe.d/dirty-frag.conf' do
  content <<~EOF
    install esp4 /bin/false
    install esp6 /bin/false
    install rxrpc /bin/false
  EOF
  mode '0644'
  owner 'root'
  group 'root'
end

%w[esp4 esp6 rxrpc].each do |mod|
  execute "rmmod-#{mod}" do
    command "rmmod #{mod}"
    only_if "lsmod | grep -q ^#{mod}"
    ignore_failure true # avoid error on failure since it fails if it's used by an application
  end
end
