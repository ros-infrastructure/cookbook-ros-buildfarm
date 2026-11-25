require 'spec_helper'

describe 'ros_buildfarm::windows_agent' do
  platform 'windows', '2019'

  before do
    stub_search('ros_buildfarm_jenkins_users', 'username:admin').and_return([{ 'password' => 'secret' }])
  end

  it 'converges and renders the WinSW service configuration' do
    expect { chef_run }.to_not raise_error
    expect(chef_run).to render_file('C:\\Users\\Administrator\\jenkins-agent-windows-service.xml')
      .with_content(/-username admin -passwordEnvVariable SWARM_PASSWORD/)
  end

  it 'starts the jenkins-agent service' do
    expect(chef_run).to start_service('jenkins-agent')
  end
end
