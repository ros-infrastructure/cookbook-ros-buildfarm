# The plugin manager runs on java, and plugins are installed for (and restart)
# the Jenkins service. Both are already set up when this recipe is included
# from ::jenkins; including them here lets it be converged on its own, as the
# plugins test suite does.
package "openjdk-#{node['jenkins']['master']['jdk_version']}-jdk-headless"
include_recipe 'jenkins::jenkins'
include_recipe 'jenkins::plugin_manager'

template "/var/lib/jenkins/plugins.txt" do
  source "plugins.txt.erb"
  mode "0644"
  owner "jenkins"
  group "jenkins"
  variables(
    plugins: node['ros_buildfarm']['jenkins']['plugins']
  )
end

execute 'install-jenkins-plugins' do
  # Refer to https://github.com/jenkinsci/plugin-installation-manager-tool for details about tool usage.
  command %w[
             java -jar /usr/local/jenkins/jars/jenkins-plugin-manager.jar
             --plugin-download-directory /var/lib/jenkins/plugins
             --plugin-file /var/lib/jenkins/plugins.txt
             --latest=false
            ]
  user "jenkins"
  notifies :restart, 'service[jenkins]', :delayed
end

execute 'remove-unlisted-jenkins-plugins' do
  # Keep everything the plugin manager resolves from plugins.txt, i.e. the
  # listed plugins plus their dependencies, and delete any other .jpi. The
  # resolved list is printed on stderr. If it comes back empty (the resolver
  # failed or its output format changed) nothing is deleted.
  list_plugins = %w[
                    java -jar /usr/local/jenkins/jars/jenkins-plugin-manager.jar
                    --plugin-download-directory /var/lib/jenkins/plugins
                    --plugin-file /var/lib/jenkins/plugins.txt
                    --latest=false
                    --list --no-download
                   ].join(' ')
  command <<~SH
    keep=$(#{list_plugins} 2>&1 >/dev/null |
           awk '/^All requested plugins:$/{f=1;next} /^$/{f=0} f{print $1".jpi"}')
    test -n "$keep" || { echo 'No resolved plugin list, not removing anything' >&2; exit 1; }
    ls | grep '\\.jpi$' | grep -vxF "$keep" | xargs -r rm -v
  SH
  cwd '/var/lib/jenkins/plugins'
  user 'jenkins'
  only_if { ::Dir.exist?('/var/lib/jenkins/plugins') }
end