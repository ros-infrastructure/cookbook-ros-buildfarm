describe service 'jenkins' do
  it { should be_running }
end

describe service 'nginx' do
  it { should be_running }
end
