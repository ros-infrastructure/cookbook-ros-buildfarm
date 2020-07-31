# InSpec test for recipe ros_buildfarm_deployment::default

# The InSpec reference, with examples and extensive documentation, can be
# found at https://www.inspec.io/docs/reference/resources/

describe port(80), :skip do
  it { should_not be_listening }
end

describe package('docker.io') do
  it { should be_installed }
end

describe package('openjdk-8-jdk-headless') do
  it { should be_installed }
end

describe package('python3-empy') do
  it { should be_installed }
end

describe package('bzr') do
  it { should be_installed }
end

describe package('git') do
  it { should be_installed }
end

describe package('mercurial') do
  it { should be_installed }
end

describe package('subversion') do
  it { should be_installed }
end

describe package('qemu-user-static') do
  it { should be_installed }
end
