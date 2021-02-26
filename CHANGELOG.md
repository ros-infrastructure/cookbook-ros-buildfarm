# ros_buildfarm CHANGELOG

This file is used to list changes made in each version of the ros_buildfarm cookbook.

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

