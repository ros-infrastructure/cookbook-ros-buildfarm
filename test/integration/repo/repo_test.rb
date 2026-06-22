# InSpec test for recipe ros_buildfarm_deployment::default

# The InSpec reference, with examples and extensive documentation, can be
# found at https://www.inspec.io/docs/reference/resources/

describe package('openssh-server') do
  it { should be_installed }
end

describe service('docker-registry') do
  it { should be_running }
end

# TODO figure out how to skip these tests when running inside kitchen-dokken.
#describe command('docker info') do
#  its('stdout') {
#    should match(%r{Registry Mirrors:[[:space:]]+http://localhost:5000})
#  }
#end
#
#describe command('docker run hello-world') do
#  its('exit_status') { should eq 0 }
#end

describe file('/var/repos/repos.key') do
  it { should exist }
  it { should be_symlink }
end

describe file('/var/repos/ubuntu/main/dists/focal/InRelease') do
  it { should exist }
end

describe command('su - jenkins-agent -c "gpg --verify /var/repos/ubuntu/main/dists/focal/InRelease"') do
  its('exit_status') { should eq 0 }
end
