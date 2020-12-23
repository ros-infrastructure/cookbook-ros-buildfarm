default['ros_buildfarm']['apt_repos']['bootstrap_url'] = 'http://repos.ros.org/repos/ros_bootstrap'
default['ros_buildfarm']['apt_repos']['bootstrap_signing_key_id'] = '8EDB2EF661FC880E'
default['ros_buildfarm']['apt_repos']['component'] = 'main'
default['ros_buildfarm']['apt_repos']['architectures'] = %w[i386 amd64 arm64 armhf source]
default['ros_buildfarm']['apt_repos']['suites'] = %w[xenial bionic focal stretch buster]
default['ros_buildfarm']['repo']['rsyncd_endpoints'] = Hash[]
default['ros_buildfarm']['repo']['container_registry_cache_enabled'] = true
