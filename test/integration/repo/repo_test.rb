# InSpec test for recipe ros_buildfarm_deployment::default

# The InSpec reference, with examples and extensive documentation, can be
# found at https://www.inspec.io/docs/reference/resources/

describe package('openssh-server') do
  it { should be_installed }
end
