# The url for the bootstrap repository used by the default configuration of the import_upstream job.
default['ros_buildfarm']['apt_repos']['bootstrap_url'] = 'http://repos.ros.org/repos/ros_bootstrap'
# The key ID used to check the signature of the bootsrap url.
default['ros_buildfarm']['apt_repos']['bootstrap_signing_key_id'] = '8EDB2EF661FC880E'
# The repository component from the bootstrap repository
default['ros_buildfarm']['apt_repos']['component'] = 'main'

# The list of architectures supported by your build farm.
default['ros_buildfarm']['apt_repos']['architectures'] = %w[i386 amd64 arm64 armhf source]

# The list of Debian and Ubuntu distributions supported by your build farm.
default['ros_buildfarm']['apt_repos']['suites'] = %w[xenial bionic focal stretch buster]

# The official buildfarm provides rsync endpoints to allow syncing between mirrors.
# Endpoints are defined in a nested hash structure with an example below
# ```
# Hash[
#   main: { comment: "ROS Main repository", path: "/var/repos/ubuntu/main" },
#   testing: { comment: "ROS Testing repository", path: "/var/repos/ubuntu/testing" },
# ]
# ```
default['ros_buildfarm']['repo']['rsyncd_endpoints'] = Hash[]

# The repository host server name is currently only used to provide
# a server name when using letsencrypt for https and is environment-specific.
default['ros_buildfarm']['repo']['server_name'] = nil

# The ros_buildfarm jobs are configured to try and pull the latest container
# image from the Docker registry at the start of each job.  To prevent that
# from consuming excess bandwidth and rate limited Docker API requests the repo
# host runs a docker registry cache intended to be used by the build farm
# hosts.
#
# The registry cache is enabled by default but in order for it to be used by
# buildfarm hosts the `node['docker']['registry_mirrors']` attribute must
# contain an entry for the cache which runs on port 5000 of the repository
# host.  For example:
# ```
# ['http://repo.test.ros.org:5000']
# ```
default['ros_buildfarm']['repo']['container_registry_cache_enabled'] = true
default['ros_buildfarm']['repo']['pulp_worker_count'] = 2
default['ros_buildfarm']['repo']['enable_pulp_services'] = true
default['ros_buildfarm']['rpm_repos']['rhel']['8'] = %w[x86_64]
default['ros_buildfarm']['rpm_repos']['bootstrap_url'] = 'http://repos.ros.org/repos/$distname/ros_bootstrap/$releasever/$basearch/'
default['ros_buildfarm']['rpm_upstream_repos']['bootstrap']['rhel']['8'] = Hash[
  architectures: %w[x86_64],
  binary: 'http://repos.ros.org/repos/rhel/ros_bootstrap/8/$basearch/',
  debug: 'http://repos.ros.org/repos/rhel/ros_bootstrap/8/$basearch/debug/',
  source: 'http://repos.ros.org/repos/rhel/ros_bootstrap/8/SRPMS/'
]
