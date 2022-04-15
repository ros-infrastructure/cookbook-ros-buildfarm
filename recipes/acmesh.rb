# Install acme.sh for certificate signing and renewal.  git is required for acme.sh's setup
package 'git'
execute 'git clone https://github.com/acmesh-official/acme.sh' do
  cwd '/root'
  not_if 'test -d /root/acme.sh'
end
execute 'acmesh-install' do
  environment 'HOME' => '/root'
  cwd '/root/acme.sh'
  cmd = './acme.sh --install --home /root/.acme.sh'
  cmd << " --accountemail #{node['ros_buildfarm']['letsencrypt_email']}" if node['ros_buildfarm']['letsencrypt_email']
  command cmd
  not_if 'test -x /root/.acme.sh/acme.sh'
end

cookbook_file "/root/cert-update-hook.sh" do
  source "cert-update-hook.sh"
  owner "root"
  group "root"
  mode "0700"
end
