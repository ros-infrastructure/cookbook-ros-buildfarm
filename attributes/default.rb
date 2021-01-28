# The public URL for your Jenkins instance
# This may be an IP address or domain name but must be resolvable and reachable from all agents.
default['ros_buildfarm']['jenkins_url'] = ''

# Docker is installed on every machine for use in Jenkins.
# If your configuration includes a docker registry cache or mirror you can configure that here.
default['docker']['registry_mirrors'] = []
