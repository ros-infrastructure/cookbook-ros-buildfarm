# The system timezone for the Jenkins host.
# Used by Jenkins to determine time in timestamped log files.
default['ros_buildfarm']['jenkins']['timezone'] = 'America/Los_Angeles'

# This cookbook provides two authentication/authorization options.
# The streamlined 'default' option uses Jenkins' own user database and a data bag of Jenkins users
# to configure a basic auth setup.
# If you want your configuration to include any other auth strategies, such as delegation to GitHub or an external auth provider you can set this auth strategy attribute to 'groovy' and add a 'auth_strategy' data bag item to configure authentication via a custom groovy script. The jenkins_users data bag is still used to set a Jenkins user for use by this cookbook and provide credentials for it to use.
default['ros_buildfarm']['jenkins']['auth_strategy'] = 'default'

# The Jenkins server name used by Jenkins internally and as the server name by the nginx reverse proxy. In order to use the Lets Encrypt features this must be a publicly resolvable domain name.
default['ros_buildfarm']['jenkins']['server_name'] = 'ros_buildfarm'

# The email address used by Jenkins as the default from-address for Jenkins emails if SMTP is enabled.
default['ros_buildfarm']['jenkins']['admin_email'] = 'noreply@ros_buildfarm'

# When set to true, acme.sh will be installed to provide SSL certificates via LetsEncrypt.org
default['ros_buildfarm']['letsencrypt_enabled'] = false

# When set to true a postfix SMTP server will be configured for use by Jenkins via sendmail.
default['ros_buildfarm']['smtp'] = false

# Last version supporting Java 8
#default['jenkins']['master']['version'] = '2.346.1'
# Last version supporting sysvinit scripts
default['jenkins']['master']['version'] = '2.319.3'
