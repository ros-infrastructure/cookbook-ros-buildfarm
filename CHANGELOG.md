# ros_buildfarm CHANGELOG

This file is used to list changes made in each version of the ros_buildfarm cookbook.

# Forthcoming

* Add support for multiple GPG key signatures on apt repositories. [#FORTHCOMING]()
  In order to allow for easier rotation of repository signing keys, we've added
  the ability to set and sign apt repositories with multiple keys. When coupled
  with a ros-archive-keyring package that supplies apt repository configuration
  this will allow for seamless updating of repository signing keys for ROS
  users. Previously, only one signing key was supported per chef environment
  and the data bag id was the name of the environment. Now, all keys matching
  `CHEF_ENVIRONMENT-IDENTIFIER` will be installed on the system and used to
  sign apt package repositories.
  It is possible to migrate your current signing key without adding any
  additional keys.
  To do so rename your current data bag item from
  `CHEF_ENVIRONMENT.json` to `CHEF_ENVIRONMENT-default.json`, update the `id`
  field of the item likewise from `CHEF_ENVIRONMENT` to
  `CHEF_ENVIRONMENT-default`, and add a `"default": true` field.

# 0.5.1

* Update plugins to resolve security issues. [#94](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/94)
* Add certificate update hook script for acme.sh. [#95](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/95)
  * Always force the renewing of the acme certificate with extra guards.
  * Add a TODO noting when the Le_ReloadCmd guard clause can be removed.
  * Test exact reloadcmd match.
  * Use correct base64 encoded script.
* Bump to pulp_rsync 0.0.3 [#100](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/100)
* Update pulp base image to use Alma Linux. [#99](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/99)
* Break out of the loop when timeout is exceeded. [#103](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/103)
* Add an SSH publish endpoint for CI archives. [#104](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/104)
* Update tested chef version to 17. [#105](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/105)
  * Update jenkins cookbook to latest.
  * Use chef 17 in CI workflows.
* Bundle publish-over-ssh plugin. [#106](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/106)
*   Block potentially abusable publish-over-ssh connection test url.
*   Bump addressable from 2.7.0 to 2.8.0
*   Update structs plugin version.
* Update seccomp profile to moby/moby 20.10.12. [#109](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/109)
* Add letsencrypt support for the repository host. [#110](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/110)
  * Add ros_buildfarm.repo.server_name attribute.
  * Extract acme.sh installation into a recipe.
  * Add letsencrypt support for repo host.
  * As of acme 3.0 letsencrypt is no longer the default but is still selectable.
* Build the pulp docker image in its own directory. [#111](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/111)
* Switch from Pulp to createrepo-agent for RPMs [#116](https://github.com/ros-infrastructure/coookbook-ros-buildfarm/pull/116)
* Add RHEL 9 repositories. [#125](https://github.com/ros-infrastructure/coookbook-ros-buildfarm/pull/125)
* Only delete S.gpg-agent if it is a symlink. [#128](https://github.com/ros-infrastructure/coookbook-ros-buildfarm/pull/128)
* Push out expiration of test keys. [#131](https://github.com/ros-infrastructure/coookbook-ros-buildfarm/pull/131)
* Constrain python packages to the versions last successfully deployed. [#130](https://github.com/ros-infrastructure/coookbook-ros-buildfarm/pull/130)
  * Apply and use constraints file in Docker build.
  * pulp-rsync can't be listed in the constraints file.
* Change default config for unattended upgrades. [#132](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/132)
* Pin the last Jenkins package which uses sysvinit scripts. [#119](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/119)
  * Add a convoluted hold and runtime check to prevent Jenkins downgrade.
  * Update jenkins cookbook to fix upstream GPG key change.
  * Make this weird case a fatal error rather.
* Use cinc for test kitchen. [#133](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/133)
  * Use cinc rather than chef workstation to run tests.
* Comment out de-listed plugin for Windows agent support. [#138](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/138)

# 0.5.0

* Update xunit and plugin dependencies for Jenkins 2.277 compatibility. [#89](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/89)
* Use systemd to manage GPG vault socket directory. [#92](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/92)
* Update plugins to address security advisories. [#91](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/91)
* Update debug output in GitHub Actions CI. [#71](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/71)
* Update Jenkins plugins for tables-to-divs changes and security advisories. [#93](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/93)
  * Fixes [#90](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/90)

# 0.4.0

- Support RHEL repositories in upload script. [#86](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/86)
- Add pulp_rsync cotnent endpoint. [#81](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/81)
- Add support for upstream RPM repositories. [#83](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/83)
- Use forked systemd-docker repository. [#80](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/80)
- Add documentation annotations to attributes. [#44](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/44)
- Use per-environment entries for secret text credentials. [#78](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/78)
- Add pulp_base_url credential. [#76](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/76)
- Add optional username for Jenkins password credentials. [#75](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/75)
- Add credentials-binding Jenkins plugin. [#73](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/73)
- Initialize empty RPM repositories. [#67](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/67)
- Restart pulp services immediately after changes. [#64](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/64)
- Add group_execute resource to execute commands within the context of auxiliary groups. [#54](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/54)
- Enable metadata signing in pulp. [#61](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/61)
- Change the pulp user to a system user with no shell. [#51](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/51)
- Force pulp to republish when signing service changes. [#58](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/58)
- Grant the pulp user access to the gpg vault. [#60](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/60)
- Fix the pulp repository name for debug repos. [#59](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/59)
- Use gpg.conf for the gpg-vault. [#53](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/53)
- Use gpg -K to initialize GNUPGHOME [#52](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/52)
- Use shellescape to escape the pulp password argument. [#56](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/56)
- Address yamllint warnings. [#62](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/62)
- Add pulp services in Docker to repo host. [#50](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/50)
- Add redirects from pulp services. [#48](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/48)

# 0.3.0

- Add smtp server support on Jenkins role using postfix and opendkim. [#9](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/9)
- Add reprepro-updater and apt repository management. [#8](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/8)
- Add jenkins user to docker group for jobs run on the Jenkins master executor. [#14](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/14)
- Fix Jenkins server name not being set due to non-matching attributes. [#13](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/13)
- Update acme.sh resources so they are only run when needed. [#10](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/10)
- Update publish-over-ssh configuration to match what Jenkins generates.  [#11](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/11)
- Update jenkins plugins for various security issues. [#16](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/16)
- Add Heavy Job jenkins plugin. [#17](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/17)
- Add rsync and rsync endpoint configuration to repo role. [#20](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/20)
- Add gpg-vault user and configuration which will eventually be used for RPM repositories. [#19](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/19)
- Remove deprecated plugins that have been removed from the Jenkins update center. [#23](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/23)
- Update Jenkins cookbook dependency to target upstream and pin. [#24](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/24) [#35](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/35)
- Disable unused CRI containerd plugin [#26](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/26)
- Fix typo in attribute name preventing the correct executor count. [#29](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/29)
- Improve reverse proxy configuration for Jenkins. [#27](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/27)
- Add ros_buildfarm_secret_text_credentials data bag and use it for the GitHub Pull Request Builder plugin. [#32](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/32)
- Update ros_buildfarm_jenkins_scripts data bag to expect environment-specific keys. [#25](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/25)
- Improve upload_trigger configuration. [#30](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/30)
- Add container registry cache on repository role. [#28](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/28)
- Update documentation for local development. [#37](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/37)
- Update jenkins role-related attribute names. [#31](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/31)
- Fix credential errors by purging fingerprint directory.  [#33](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/33)
- Check the signature of the ROS bootstrap repository on import. [#36](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/36)
- Restart dockerd when containerd is restarted. [#34](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/34)
- Install pulp client packages on agent role. [#41](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/41)
- Add custom seccomp profile for Docker. [#39](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/39)
- Add docker cleanup script. [#40](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/40)
- Update private key credentials data bag to expect environment-specific keys. [#42](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/42)
- Store Jenkins credentials in a file rather than in the environment. [#45](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/45)
- Set HOME variable during acme.sh usage in case chef is run by non-root user. [#43](https://github.com/ros-infrastructure/cookbook-ros-buildfarm/pull/43)

# 0.2.0

First release with three recipes for the three different machine types.

# 0.1.0

Initial release.
- Add recipe for linux agents.

