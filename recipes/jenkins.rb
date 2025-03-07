## Jenkins Server ##


# Normalize attribute hierarchy
# Some attributes were inconsistently nested in the ros_buildfarm cookbook.
# The default and expected attributes have been changed but in order
# to remain compatible with existing configurations a warning is being added
# if the old attributes are set and differ from the new ones.
%w(admin_email server_name).each do |attr|
  if node['ros_buildfarm'][attr] # the old attribute is defined
    if node['ros_buildfarm']['jenkins'][attr].nil?
      Chef::Log.warn(
        "The attribute `node['ros_buildfarm']['#{attr}']` is now `node['ros_buildfarm']['jenkins']['#{attr}']`. " +
        "Support for the previous attribute may be removed in a future release of this cookbook. " +
        "Replacing the `node['ros_buildfarm']['#{attr}']` attribute with `node['ros_buildfarm']['jenkins']['#{attr}']` is recommended."
      )
      node.default['ros_buildfarm']['jenkins'][attr] = node['ros_buildfarm'][attr]
    elsif node['ros_buildfarm']['jenkins'][attr] != node['ros_buildfarm'][attr]
      Chef::Log.warn(
        "The attribute `node['ros_buildfarm']['#{attr}']` is now `node['ros_buildfarm']['jenkins']['#{attr}']`. " +
        "Support for the previous attribute may be removed in a future release of this cookbook. " +
        "Removing the `node['ros_buildfarm']['#{attr}']` attribute is recommended."
      )
      node.default['ros_buildfarm'][attr] = node['ros_buildfarm']['jenkins'][attr]
    end
  end
end

# Run an apt update if one hasn't been run in 24 hours (the default frequency).
# Without this the recipe fails on AWS instances with empty apt caches.
apt_update

# Parametrize java version from attributes
jdk_version = node.default['jenkins']['master']['jdk_version']
package "openjdk-#{jdk_version}-jdk-headless"

# Jenkins downgrade protection
#
# The Jenkins package has transitioned to using systemd units instead of
# sysvinit style init scripts. In order to maintain this cookbook the last
# version of Jenkins which is packaged with a sysvinit script is pinned.
# However Jenkins cannot be safely downgraded and some configurations of
# Jenkins will continue to function once initially configured even after the
# systemd switch.
# To protect users from unintentional downgrades we're going to do something really ugly here.
package 'jenkins' do
  action :lock
  only_if { -> do
    jenkins_info = `dpkg -s jenkins`
    if $?.exitstatus != 0
       return false
    end

    version_line = jenkins_info.lines.select{|line| line =~ /^Version: /}.first
    if version_line.nil?
      Chef::Log.fatal("Could not determine Jenkins version from dpkg but it does seem installed.")
      raise
    end

    # Transform "Version: 2.319.1\n" to ["2", "319", "1"]
    version_components = version_line.chomp.split(": ")[1].split(".")
    # The first systemd versions are 2.335 (weekly) and 2.332.1 (LTS)
    if version_components[0].to_i > 2 or version_components[1].to_i >= 332
      node.run_state[:jenkins_package_version_lock] = version_components.join('.')
      Chef::Log.warn("Chef detected this Jenkins version: #{node.run_state[:jenkins_package_version_lock]}")
      return true
    end
    # Jenkins is installed but is older than the maximum and can be upgraded.
    return false
  end.call }
end

ruby_block 'prevent jenkins downgrade' do
  block do
    if node.run_state[:jenkins_package_version_lock]
      if node['jenkins']['master']['version'] != node.run_state[:jenkins_package_version_lock]
        Chef::Log.fatal("Before this cookbook continues, please set the node['jenkins']['master']['version'] attribute to #{node.run_state[:jenkins_package_version_lock]} or this cookbook will attempt to downgrade your Jenkins version.")
        Chef::Log.fatal("See https://github.com/ros-infrastructure/cookbook-ros-buildfarm/issues/121 for more information")
        raise
      end
    end
  end
end

include_recipe 'jenkins::jenkins'

# Set up authentication
chef_user = search('ros_buildfarm_jenkins_users', 'chef_user:true').first
node.run_state[:jenkins_username] = chef_user['username']
node.run_state[:jenkins_password] = chef_user['password']
node.default['jenkins']['executor']['protocol'] = 'http'

# Install plugins required to run ros_buildfarm.
include_recipe '::plugins'

## Jenkins configuration
# Most of our Jenkins configuration has been consolidated into this one yaml
# file thanks to the Jenkins configuration-as-code plugin which provides a
# stable interface to Jenkins' internal describable and data binding APIs.
# This decreases the configuration file drift based on plugin version artifacts
# and consolidates everything in to the single file.
template '/var/lib/jenkins/jenkins.yaml' do
  source 'jenkins/jenkins.yaml.erb'
  owner node['jenkins']['master']['user']
  group node['jenkins']['master']['group']
  variables Hash[
    scheme: if node['ros_buildfarm']['letsencrypt_enabled'] then 'https' else 'http' end,
    server_name: node['ros_buildfarm']['jenkins']['server_name'],
    admin_email: node['ros_buildfarm']['jenkins']['admin_email'],
  ]
  notifies :restart, 'service[jenkins]', :immediately
end

## Configuration for the publish-over-ssh plugin.
# TODO: (nuclearsandwich) This is going to require re-organization to suite an all-in-one setup as
# the agent username attribute for the repo host specifically will change.
node.default['ros_buildfarm']['ssh_publisher']['repo_username'] = node['ros_buildfarm']['agent']['agent_username']
# By default we rely expect the repo host to be used for each of the other duties with different remote root directories.
# This bit of Ruby metaprogramming here makes me nervous in a chef recipe.
# I am doing it anyway because I can't bring myself to copy the logic.
# In the long term I expect that this entire configuration may need to be re-thought but for now we're porting it more or less directly from the existing buildfarm_deployment.
%w(hostname username port timeout).each do |attr|
  unless node['ros_buildfarm']['ssh_publisher']["docs_#{attr}"]
    node.default['ros_buildfarm']['ssh_publisher']["docs_#{attr}"] = node['ros_buildfarm']['ssh_publisher']["repo_#{attr}"]
  end
  unless node['ros_buildfarm']['ssh_publisher']["rosdistro_cache_#{attr}"]
    node.default['ros_buildfarm']['ssh_publisher']["rosdistro_cache_#{attr}"] = node['ros_buildfarm']['ssh_publisher']["repo_#{attr}"]
  end
  unless node['ros_buildfarm']['ssh_publisher']["status_page_#{attr}"]
    node.default['ros_buildfarm']['ssh_publisher']["status_page_#{attr}"] = node['ros_buildfarm']['ssh_publisher']["repo_#{attr}"]
  end
end
# Sadly the publish-over-ssh plugin does not completely implement the necessary
# APIs so we have to fall back to the XML configuration file.
template '/var/lib/jenkins/jenkins.plugins.publish_over_ssh.BapSshPublisherPlugin.xml' do
  source 'jenkins/jenkins.plugins.publish_over_ssh.BapSshPublisherPlugin.xml.erb'
  owner node['jenkins']['master']['user']
  group node['jenkins']['master']['group']
  variables Hash[
    plugin_version: node['ros_buildfarm']['jenkins']['plugins']['publish-over-ssh'],
    ssh_key: data_bag_item('ros_buildfarm_publish_over_ssh_key', node.chef_environment)['private_key']
  ]
  notifies :restart, 'service[jenkins]', :immediately
end

# Jenkins authentication.
# This cookbook currently supports two modes of authentication:
# * Jenkins default:
#   This method uses the Jenkins internal user database and manages permissions directly with chef.
# * Groovy scripted:
#   This method can be used to enable more complex authentication / authorization strategies and security realms.

# Create init.groovy.d directory to save important groovy files
directory '/var/lib/jenkins/init.groovy.d' do
  mode '0500'
  owner 'jenkins'
  group 'jenkins'
end

if node['ros_buildfarm']['jenkins']['auth_strategy'] == 'groovy'
  auth_strategy_script = data_bag_item('ros_buildfarm_jenkins_scripts', 'auth_strategy')[node.chef_environment]
  if auth_strategy_script.nil?
    Chef::Log.fatal("No auth strategy script for #{node.chef_environment} in ros_buildfarm_jenkins_scripts but auth_strategy is set to groovy.")
    raise
  end

  file '/var/lib/jenkins/init.groovy.d/auth_strategy.groovy' do
    content auth_strategy_script['command']
    mode '0500'
    owner 'jenkins'
    group 'jenkins'
  end
elsif node.default['ros_buildfarm']['jenkins']['auth_strategy'] == 'default'
  default_auth_script = <<~GROOVY
    import hudson.model.*
    import jenkins.model.*
    import hudson.security.HudsonPrivateSecurityRealm
    import hudson.security.SecurityRealm

    def jenkins = Jenkins.getInstance()
    // Boolean `!` binds closer than instanceof so parenthesize the instanceof operation
    if (!(jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
      jenkins.setSecurityRealm(new HudsonPrivateSecurityRealm(false))
      jenkins.save()
    }
  GROOVY

  file '/var/lib/jenkins/init.groovy.d/auth_strategy.groovy' do
    content default_auth_script
    mode '0500'
    owner 'jenkins'
    group 'jenkins'
  end

  # Restart jenkins after updating the security realm otherwise running without
  # authentication yields 403 errors when configuring.
  service 'jenkins' do
    action :restart
  end

  # Aggregate permissions to assign to each user with a groovy script.
  users_creation_scripts = [
    default_auth_script
  ]

  permissions = []
  data_bag('ros_buildfarm_jenkins_users').each do |id|
    user = data_bag_item('ros_buildfarm_jenkins_users', id)

    if user['permissions']
      user['permissions'].each do |perm|
        permissions << [perm, user['username']]
      end
    end

    # Create users unless the username is anonymous.
    # An anonymous user is used to set permissions for anonymous users but I do
    # not know what would happen if we tried to create a concrete user with the
    # username anonymous so let's just don't.
    next if user['username'] == 'anonymous'

    user_creation_script = <<~GROOVY
      user = hudson.model.User.get("#{user['username']}")
      if (#{!user['email'].nil?}) {
        email = new hudson.tasks.Mailer.UserProperty("#{user['email']}")
        user.addProperty(email)
      }
      password = hudson.security.HudsonPrivateSecurityRealm.Details.fromPlainPassword("#{user['password']}")
      user.addProperty(password)
      keys = new org.jenkinsci.main.modules.cli.auth.ssh.UserPropertyImpl(#{user['public_keys'].join('\n')})
      user.addProperty(keys)
      user.save()
    GROOVY

    users_creation_scripts << user_creation_script
  end

  matrix_auth_permissions_script = <<~GROOVY
      import hudson.security.ProjectMatrixAuthorizationStrategy

      matrix_auth = new ProjectMatrixAuthorizationStrategy()

      #{permissions.map { |p, u| "matrix_auth.add(#{p}, \"#{u}\")" }.join "\n"}

      if (!matrix_auth.equals(jenkins.getAuthorizationStrategy())) {
        jenkins.setAuthorizationStrategy(matrix_auth)
        jenkins.save()
      }
    GROOVY

  users_creation_scripts << matrix_auth_permissions_script

  file '/var/lib/jenkins/init.groovy.d/auth_strategy.groovy' do
    content users_creation_scripts.join("\n")
    mode '0500'
    owner 'jenkins'
    group 'jenkins'
  end
else
  Chef::Log.warn("Jenkins auth_strategy attribute `#{node['ros_buildfarm']['jenkins']['auth_strategy']}` is unknown. No authentication will be configured.")
end

timezone node['ros_buildfarm']['jenkins']['timezone']

## Configure web proxy ##
package 'nginx'
service 'nginx' do
  action [ :enable, :start]
end
# Disable the default debian server.
file '/etc/nginx/sites-enabled/default' do
  action :delete
  manage_symlink_source false
end

if node['ros_buildfarm']['letsencrypt_enabled']
  server_name = node['ros_buildfarm']['jenkins']['server_name']
  cert_path = "/etc/ssl/certs/#{server_name}/fullchain.pem"
  key_path = "/etc/ssl/private/#{server_name}.key"

  # Bootstrap https with self-signed certificates
  package 'ssl-cert'
  directory "/etc/ssl/certs/#{server_name}"

  execute "cp /etc/ssl/certs/ssl-cert-snakeoil.pem #{cert_path}" do
    not_if "test -r #{cert_path}"
  end
  execute "cp /etc/ssl/private/ssl-cert-snakeoil.key #{key_path}" do
    not_if "test -r #{key_path}"
  end

  template '/etc/nginx/sites-enabled/jenkins' do
    source 'nginx/jenkins-webproxy.ssl.conf.erb'
    variables Hash[
      server_name: node['ros_buildfarm']['jenkins']['server_name'],
      cert_path: cert_path,
      key_path: key_path,
    ]
    notifies :restart, 'service[nginx]', :immediately
  end

  include_recipe "ros_buildfarm::acmesh"

  # Create Let's Encrypt signed cert if it has not already been done.
  execute 'acme-issue-cert' do
    environment 'HOME' => '/root'
    command %W(
      /root/.acme.sh/acme.sh --issue
      --webroot /var/www/html
      --domain #{server_name}
      --fullchain-file #{cert_path}
      --key-file #{key_path}
      --reloadcmd /root/cert-update-hook.sh
      --server letsencrypt
      --force
    )
    not_if {
      # TODO the second guard clause can be removed after >= 0.6.0
      File.directory?("/root/.acme.sh/#{server_name}") and
      File.read("/root/.acme.sh/#{server_name}/#{server_name}.conf").match(/Le_ReloadCmd='__ACME_BASE64__START_L3Jvb3QvY2VydC11cGRhdGUtaG9vay5zaA==__ACME_BASE64__END_'/)
    }
  end
else
  template '/etc/nginx/sites-enabled/jenkins' do
    source 'nginx/jenkins-webproxy.http.conf.erb'
    variables Hash[
      server_name: node['ros_buildfarm']['jenkins']['server_name']
    ]
    notifies :restart, 'service[nginx]'
  end
end

package 'python3-yaml'

package 'docker.io'

# Setup credentials

credentials_scripts = [
  <<~GROOVY
    import jenkins.model.*
    import com.cloudbees.plugins.credentials.*
    import com.cloudbees.plugins.credentials.impl.*
    import com.cloudbees.plugins.credentials.common.*
    import com.cloudbees.plugins.credentials.domains.*
    import com.cloudbees.jenkins.plugins.sshcredentials.impl.*
    import hudson.util.Secret;
    import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl;
    import org.jenkinsci.plugins.plaincredentials.StringCredentials;

    global_domain = Domain.global()
    credentials_store = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

    available_credentials = CredentialsProvider.lookupCredentials(
      StandardUsernameCredentials.class,
      Jenkins.getInstance(),
      hudson.security.ACL.SYSTEM,
      new SchemeRequirement("ssh")
    )
  GROOVY
]

data_bag('ros_buildfarm_password_credentials').each do |item|
  password_credential = data_bag_item('ros_buildfarm_password_credentials', item)

    credentials_scripts << <<~GROOVY
      credentials = new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        "#{password_credential['id']}",
        "#{password_credential['description']}",
        "#{password_credential['username'] if password_credential['username']}",
        "#{password_credential['password']}"
      )
      existing_credentials = CredentialsMatchers.firstOrNull(
        available_credentials,
        CredentialsMatchers.withId("#{password_credential['id']}")
      )

      if (existing_credentials != null) {
      credentials_store.updateCredentials(
        global_domain,
        existing_credentials,
        credentials
      )
      } else {
        credentials_store.addCredentials(global_domain, credentials)
      }
    GROOVY
end

data_bag('ros_buildfarm_private_key_credentials').each do |item|
  private_key_credential = data_bag_item('ros_buildfarm_private_key_credentials', item)[node.chef_environment]

    credentials_scripts << <<~GROOVY
      private_key = """#{private_key_credential['private_key']}
      """

      credentials = new BasicSSHUserPrivateKey(
        CredentialsScope.GLOBAL,
        "#{private_key_credential['name']}",
        "#{private_key_credential['username'] if private_key_credential['username']}",
        new BasicSSHUserPrivateKey.DirectEntryPrivateKeySource(private_key),
        "#{private_key_credential['passphrase'] if private_key_credential['passphrase']}",
        "#{private_key_credential['description']}"
      )
      existing_credentials = CredentialsMatchers.firstOrNull(
        available_credentials,
        CredentialsMatchers.withId("#{private_key_credential['id']}")
      )

      if (existing_credentials != null) {
      credentials_store.updateCredentials(
        global_domain,
        existing_credentials,
        credentials
      )
      } else {
        credentials_store.addCredentials(global_domain, credentials)
      }
    GROOVY
end

data_bag('ros_buildfarm_secret_text_credentials').each do |item|
  secret_text_credential = data_bag_item('ros_buildfarm_secret_text_credentials', item)[node.chef_environment]
    credentials_scripts << <<~GROOVY
      secret = new Secret("#{secret_text_credential['secret_text']}")

      credentials = new StringCredentialsImpl(
        CredentialsScope.GLOBAL,
        "#{secret_text_credential['name']}",
        "#{secret_text_credential['description']}",
        secret
      )

      available_secret_text = CredentialsProvider.lookupCredentials(
        StringCredentials.class,
        Jenkins.getInstance(),
        hudson.security.ACL.SYSTEM
      ).findAll({
        it.secret == secret &&
        it.description == "#{secret_text_credential['description']}"
      })

      existing_credentials = available_secret_text.size() > 0 ? available_secret_text[0] : null

      if (existing_credentials != null) {
        credentials_store.updateCredentials(
          global_domain,
          existing_credentials,
          credentials
        )
      } else {
        credentials_store.addCredentials(global_domain, credentials)
      }
    GROOVY
end

file '/var/lib/jenkins/init.groovy.d/credentials_config.groovy' do
  content credentials_scripts.join("\n")
  mode '0500'
  owner 'jenkins'
  group 'jenkins'
end

file '/var/lib/jenkins/init.groovy.d/99-approved_signatures.groovy' do
  content <<~GROOVY
  import org.jenkinsci.plugins.scriptsecurity.scripts.*
  ScriptApproval scriptApproval = ScriptApproval.get()
  scriptApproval.clearApprovedSignatures()

  ["field hudson.model.View name",
  "field java.util.ArrayList size",
  "method groovy.lang.Binding getVariables",
  "method groovy.lang.Script println java.lang.Object",
  "method hudson.XmlFile getFile",
  "method hudson.model.AbstractBuild getWorkspace",
  "method hudson.model.AbstractItem getConfigFile",
  "method hudson.model.AbstractItem updateByXml javax.xml.transform.stream.StreamSource",
  "method hudson.model.AbstractProject getUpstreamProjects",
  "method hudson.model.AbstractProject isDisabled",
  "method hudson.model.BuildableItem scheduleBuild hudson.model.Cause",
  "method hudson.model.Item delete",
  "method hudson.model.Item getName",
  "method hudson.model.ItemGroup getAllItems",
  "method hudson.model.Job getLastBuild",
  "method hudson.model.Job getNextBuildNumber",
  "method hudson.model.Job isBuilding",
  "method hudson.model.Job isInQueue",
  "method hudson.model.ModifiableViewGroup addView hudson.model.View",
  "method hudson.model.Result isWorseOrEqualTo hudson.model.Result",
  "method hudson.model.Run getNumber",
  "method hudson.model.Run getResult",
  "method hudson.model.View updateByXml javax.xml.transform.Source",
  "method hudson.model.View writeXml java.io.OutputStream",
  "method hudson.model.ViewGroup getViews",
  "method java.io.File getName",
  "method java.io.File getPath",
  "method java.io.File listFiles",
  "method java.lang.Thread isInterrupted",
  "method javax.xml.parsers.DocumentBuilder parse java.io.File",
  "method javax.xml.parsers.DocumentBuilder parse java.io.InputStream",
  "method javax.xml.parsers.DocumentBuilder parse org.xml.sax.InputSource",
  "method javax.xml.parsers.DocumentBuilderFactory newDocumentBuilder",
  "method jenkins.model.HistoricalBuild getNumber",
  "method jenkins.model.HistoricalBuild getResult",
  "method jenkins.model.Jenkins getAllItems",
  "method jenkins.model.Jenkins getItemByFullName java.lang.String",
  "method jenkins.model.Jenkins rebuildDependencyGraph",
  "method jenkins.model.ModifiableTopLevelItemGroup createProjectFromXML java.lang.String java.io.InputStream",
  "method jenkins.model.ParameterizedJobMixIn\\$ParameterizedJob isDisabled",
  "method org.apache.xml.serialize.DOMSerializer serialize org.w3c.dom.Document",
  "method org.apache.xml.serialize.OutputFormat setIndent int",
  "method org.apache.xml.serialize.OutputFormat setIndenting boolean",
  "method org.w3c.dom.Document getElementsByTagName java.lang.String",
  "method org.w3c.dom.Document importNode org.w3c.dom.Node boolean",
  "method org.w3c.dom.Element getElementsByTagName java.lang.String",
  "method org.w3c.dom.Node appendChild org.w3c.dom.Node",
  "method org.w3c.dom.Node setTextContent java.lang.String",
  "method org.w3c.dom.NodeList getLength",
  "method org.w3c.dom.NodeList item int",
  "new hudson.model.Cause\\$UpstreamCause hudson.model.AbstractBuild",
  "new java.io.ByteArrayOutputStream",
  "new java.io.File java.lang.String",
  "new java.io.StringBufferInputStream java.lang.String",
  "new java.lang.InterruptedException java.lang.String",
  "new javax.xml.transform.stream.StreamSource java.io.Reader",
  "new org.apache.xml.serialize.OutputFormat org.w3c.dom.Document",
  "new org.apache.xml.serialize.XMLSerializer java.io.Writer org.apache.xml.serialize.OutputFormat",
  "new org.xml.sax.InputSource java.io.Reader",
  "staticMethod com.github.difflib.DiffUtils diff java.util.List java.util.List",
  "staticMethod com.github.difflib.UnifiedDiffUtils generateUnifiedDiff java.lang.String java.lang.String java.util.List com.github.difflib.patch.Patch int",
  "staticMethod difflib.DiffUtils diff java.util.List java.util.List",
  "staticMethod difflib.DiffUtils generateUnifiedDiff java.lang.String java.lang.String java.util.List difflib.Patch int",
  "staticMethod hudson.model.View createViewFromXML java.lang.String java.io.InputStream",
  "staticMethod java.lang.System getProperty java.lang.String",
  "staticMethod java.lang.Thread currentThread",
  "staticMethod javax.xml.parsers.DocumentBuilderFactory newInstance",
  "staticMethod jenkins.model.Jenkins getInstance",
  "staticMethod org.codehaus.groovy.runtime.DefaultGroovyMethods getText java.io.File java.lang.String",
  "staticMethod org.codehaus.groovy.runtime.DefaultGroovyMethods multiply java.lang.String java.lang.Number",
  "staticMethod org.codehaus.groovy.runtime.DefaultGroovyMethods println groovy.lang.Closure java.lang.Object",
  "staticMethod org.codehaus.groovy.runtime.DefaultGroovyMethods sort java.lang.Object[]"].each { signature ->
    scriptApproval.approveSignature(signature)
  }

  ["SHA512:09560477443262f4746357aee61058ddd6019beb6ff02e4b919729279945194459ea60ff2fba0dc2951362fef7b9fe89667d1645518aef6d656870e9683760fd",
  "SHA512:0c9f33553902166e83baf4df9f82b7e63c3541d235b4ccdcfa3e244add67fcc19bb7c730246cf319db99b0a3e9aacbc1e4bf2b58208608769202e83da700bb5d",
  "SHA512:0cd2dcb7cf87d8e6437fa42a0dd7c337cfbd9e1f654e95ab53af4fbb384a2d25f9176fb17dec9765b8326b4781d3b1f1d77dfbfe878434ca0bb207217a8808b9",
  "SHA512:0f5a96cad4ef562b766abc81129c3bfd9d024b069bd64980d1f24b69760b276c65e27553802d464e7a7d72f3a33c1dac4229ccb42622bf619f3bf88b1d680f8d",
  "SHA512:1351300384ad1c6d05ec6f8d415d178a0ca2017f574dfc432c656727f7e9df9e1a4f1268112fc8a4baee42754d88f7b349be47216cf9a962e37b044f71927498",
  "SHA512:172ca66651bec914580533f3fc76ad9547bc4e2815f4d0bbe2f9a431c7f60348a719fd2f74e7c105ac2efdc91439f2d804c92ce0eca2123d95453a32deeec983",
  "SHA512:18d75418504b56e9c09fb2d1419dc3381db46b0258b0e542453ecac057dbf300f6f6ab6d70cb965c017bff02885a4b4650b0d3fd19c1a5db2e9ed0723b8998cf",
  "SHA512:18e84678aa1575e1438811d0447563ea6bde0f2a44675a02821509c896674ba8455007b38ec06dc93751c9661319a1e797c751750d121f717b6fad997b15cfa1",
  "SHA512:195adb9cfaeb05f718a8f364714378824b44b477c3ef4b6f9406a42aa39a5892fa8689bf8861a7301d88ae8f813e8e656ca80416bda923aa7955813ec87ce75b",
  "SHA512:23b9f9f82fb3f8699beaccd3bfd36d8888b2011401641a0a514491467020e93923c6de3f6fe35007d9271e6257ee2519d43130bf4a026ae538d87fbbf557d7bb",
  "SHA512:3bd84ad6b5f4714b60c7d4979737352ffc5c1d32fd35f2d48ed405751a4903ea367d7c7fe31ae37294271e3bce44194c4b801388d6a067353c1ac6b36e81d141",
  "SHA512:4530aad9d71765158830a654ae4367b28c635385035a24850bc4a08b9be3a2715c065dad34395402138602f49c11c1be01aa0a529179d1bfd36ec5ba70ea449b",
  "SHA512:586cde1b84a637fb0ceec2ea2faeb4a04802edd1a5d3177ba217afdf777af19b4080b47ba5294c3b89c943e8e5a449de0ed2d2811c80c95fc30678b861b09695",
  "SHA512:712f87b9eb5c498735ce9aa870e7c7f2b4b1d16533205fa5290424a7b08761b086b3033dcb803781d1449887da7d27a4e47b522b9162d541f4b416ec1eccb576",
  "SHA512:72cf62562813c47e6ecb0488550a2b3d6a73bd5465c09dc616a10dd029e2457944181b3ecc5adb9c6f941a2d033cdba6f1c802fd80df317b1b7f163eef587181",
  "SHA512:76510030a9858cb8fbcc10a22853726f90f4c5037ab84d31827d7d98cd60d38bb624ba2bad8856f656d333ca0ba6469c31c0c27e69c4b6d8441cf49693cfad29",
  "SHA512:81b1efad345f195c226ebf290cbd7f44bf54838e76055c2608b8447bd16319679dc739eec6a62c095e346698cb109eede1662ca4d1edd1575a1d81241ac1a5df",
  "SHA512:97c7471c4c1175467cea3223665e342c085ec4d738d6678d077fc8f9764e6718f8f8aa9307df8f62ea8934e4f37af086816f634197a91379f6a0b3dc8d1ed216",
  "SHA512:9ae2ce59b9b48d352f85f56d14bf4e9933554b2972b9ff1defbe3bbf27151fd614b2b527e870dd0f5ddd05f9e8f2c78706d77b62916aac93811a31fbd62fcd6d",
  "SHA512:aaf44300af8d37695e488a43064c7afcc8f7ac41f3a9099f08e5a020446979466ad22e86b258f7317479c0347c075808fda5fce9dba3b40d380c3247d332b8f0",
  "SHA512:ac9c696420eee611ea3dc571f2fb5aba6d08cb6e0873ab9e4ebeac99a6349b99e948b32e7f7a4c997aa2756f071c8ff01835f8be3b386149c7043f6aed4d9823",
  "SHA512:b2df135d2a25faa9c3b4e09761e2f64fe9e76ba30449b751c682562efca099de17d512e87463b3e26f1d308e1c99c12150d0666e9a1b9efbb7cc52fa383d9b87",
  "SHA512:b86ecbae1b2e192c40a3fb74e447e427ac1ed10e872a14b7dcc86eb6285a8c5b93b8e90291604b905ac8992f2068f1ff6f1ed4405759ee553de54bef73e6681a",
  "SHA512:bd13b588bf0743a5a23195ab5a512b8657f89cf0b3296665614ffac5921ffdaf697555164c8fbc8f57fea878c2d8ce7c292adba4af59477dd8e42a0907406b83",
  "SHA512:be515fa11b98632a93a849f4b97a1da6f63814a8ef78abb3ad8d8d5806d216fc068d35632f7eff4460568f3188ce9744deb8ea870b9693d156a8189844a73088",
  "SHA512:c80db5315ee6804e25926b1d069af9048efa1f163b720ae151b4cfe21591ee410d98bc1a85d7b95f5eb761105bab9502b5758d2b6b3d19f82293aa58bff3c10e",
  "SHA512:c923818e40e920b7a4076532df72b12920b050aeea6a6d2d9441871597466fbd4a05d4053b1e8edd3ca38213084f6c6ae4b1b2c0c8211045022bb6993fcdd174",
  "SHA512:cab2d4c81648d403ba03de9925db157d56604c7a39ca4bb96adc4ffb0afbe0967f9e8cf6f5ea50e61212adc34a766d1cd08051bb30cbda03fd1ea4ee6c8501d4",
  "SHA512:d3526b226c4d21ffc517d2aaa20b229e7343ba9ea5e76336428d358e010cb40be7b65c81257b5b370f5fdfd4c46c2e83538f8c24b26d392272babc51ec66293f",
  "SHA512:d35689a3c9000c8dc2d133aed1713f0e246a33cea6b058a3742cacbd0ad3b1c84200bee93cfd2a887c5aff6747637423bb79d78d74229ed546aa0fd74bf6b861",
  "SHA512:d5cdf62858fbc3f54afa1c6990e165ec09f649ee054cc65878db2ce8b26fdcddacaabaed3be07a1657ab4371229e2cd74a9815016f88c54345bc6247b25567d1",
  "SHA512:d7cac6334d507b89a85d01f02561247cedab14348cd284827b6d4f92ef54d18f556dff2dd4ccab8dce15335edcd03ae13b2a9763ba896804420fdd9c5834fc25",
  "SHA512:dda01e1a34c9f74f78e6668227649202b12ffb3ae79371423a101dd0de5f49530ee957c02984153bd7083ac84784b415868c81658ea81ff74870734371f8b374",
  "SHA512:f032afb2586a528370131fb01314f7477c421d187f2608e12432b6762491041add9e27be256179cc880b7c6e2c133076a032619d090455826946a6089af6f816",
  "SHA512:f546341804eb0d3832d8a597958c24cce4100bcce080000293f5d2a46f6ae66f3c9fbf91cd3fe777f774005e4e2bab09f92d617cdc9fb451a1f5874c2e74e3ba",
  "SHA512:f6b4ff28149d73e66de15c13951d1fcec83eeecd6bb6993061a99b09a114310b93a3f724f9261f142277b79799a5a3bb9012c22f66403e5d8c885a4c6a6c50c0"].each { hash ->
    scriptApproval.approveScript(hash)
  }
  scriptApproval.save()
  GROOVY
  mode '0500'
  owner 'jenkins'
  group 'jenkins'
end

# Remove Jenkins fingerprint files
# Jenkins tracks the fingerprints of certain files so that different jobs may use different versions.
# The chef credential resources do not seem idempotent in the face of existing credentials so when chef
# is run and they are updated the fingerprint of the credential changes which causes an issue with jobs
# using them.
# I would like to find a more elegant solution, either of getting Jenkins to use the current version
# if the fingerprinted file is missing or making the credential resources idemponent. I'm not sure
# if that's possible however given that Jenkins will encrypt sensitive data with an instance-specific key.
# For now we are clobbering the fingerprints directory and hoping we get away with it. Unfortunately
# this requires yet another Jenkins restart
service 'jenkins' do
  action :stop
end
directory '/var/lib/jenkins/fingerprints' do
  action :delete
  recursive true
end
directory '/var/lib/jenkins/fingerprints' do
  owner 'jenkins'
  group 'jenkins'
end

# Groovy system scripts use the master node user, i.e., jenkins (See ros_buildfarm/templates/snippet/builder_system-groovy.xml).
# This is a problem, as the reconfigure jobs need access to views under jenkins-agent user workspace
# Everything under /home/jenkins-agent has 750 permissions, so jenkins user does not have access by default.
# Adding jenkins to the group will give the jenkins admin access to the jenkins agent data.
group 'jenkins-agent' do
  members ['jenkins']
  append true
  action :manage
end
service 'jenkins' do
  action :start
end

# Configure agent on jenkins
# TODO: (nuclearsandwich) This is going to require re-organization to suite an all-in-one setup.
node.default['ros_buildfarm']['agent']['nodename'] = 'agent_on_jenkins'
node.default['ros_buildfarm']['agent']['executors'] = 1
node.default['ros_buildfarm']['agent']['labels'] = %w(agent_on_master agent_on_jenkins)
node.default['ros_buildfarm']['jenkins_url'] = 'http://localhost:8080/'

## Postfix and OpenDKIM for SMTP
if node['ros_buildfarm']['smtp']
  include_recipe '::_jenkins_smtp'
end

include_recipe '::agent'

group 'docker' do
  members ['jenkins']
  append true
  action :manage
end
