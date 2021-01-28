# ros_buildfarm

Installs and configures ROS build farm machines.

## Requirements

* Ubuntu 20.04.
* [Chef Infra](https://www.chef.io/products/chef-infra) or [Cinc client](https://cinc.sh/start/client/) 15
* [Jenkins cookbook](https://supermarket.chef.io/cookbooks/jenkins)


## Usage

This cookbook is primarily tested using chef-solo / cinc-solo for deployment onto fresh Ubuntu 20.04 virtual machines.
Use with chef server is not tested but should work.

To set up a ROS build farm cluster using this cookbook see the example chef configuration repository in [chef-ros-buildfarm].

[chef-ros-buildfarm]: https://github.com/ros-infrastructure/chef-ros-buildfarm

## Recipes

This cookbook is currently organized with one recipe per machine role:
* jenkins
* repo
* agent

## Developement

This cookbook uses [Test Kitchen](https://kitchen.ci) for development and testing.
We recommend installing the [Cinc Workstation](https://cinc.sh/start/workstation/) from the [Cinc](https://cinc.sh) project, a community distribution of Chef software.
To use the default Test Kitchen driver, you will also need [Vagrant](https://www.vagrantup.com) and [Virtualbox](https://www.virtualbox.org/) configured.

`kitchen test` will set up, converge with chef, test, and then tear down instances for each recipe.
When developing new changes, it is often quicker to run the converge step repeatedly for only the recipe you are developing.
For example `kitchen converge repo` will run the repo recipe on an existing instance.
This is helpful for faster iteration and since chef recipes should be idempotent the repeated run should not break anything.
Once development is complete it's a good idea to run a clean `kitchen test repo` to verify that the recipe still converges in a single pass.

You can also use the kitchen-dokken or kitchen-ec2 drivers by overriding the KITCHEN_LOCAL_YAML environment variable. For example:
```
env KITCHEN_LOCAL_YAML=kitchen.dokken.yml kitchen converge repo

```

To get a shell on one of the test instances for investigating issues, use the `kitchen login`. For example
```
kitchen login jenkins
```

### Installing test kitchen with RubyGems

If the chef workstation isn't available for your platform you can install test kitchen with RubyGems and Bundler.
You'll need Ruby, ideally Ruby 2.7, RubyGems, and Bundler.

Run `bundle install` to install the gems declared in `gems.rb`.
In order to use test kitchen from bundler all kitchen commands must be prefixed with `bundle exec`. For example:
```
bundle exec kitchen test repo
```


