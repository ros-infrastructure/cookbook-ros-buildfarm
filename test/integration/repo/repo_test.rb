# InSpec test for recipe ros_buildfarm_deployment::default

# The InSpec reference, with examples and extensive documentation, can be
# found at https://www.inspec.io/docs/reference/resources/

describe package('openssh-server') do
  it { should be_installed }
end

describe service('docker-registry') do
  it { should be_running }
end

describe command('docker info') do
  its('stdout') {
    should match(%r{Registry Mirrors:[[:space:]]+http://localhost:5000})
  }
end

describe command('docker run hello-world') do
  its('exit_status') { should eq 0 }
end
