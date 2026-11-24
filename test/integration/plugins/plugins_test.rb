# Verifies recipes/plugins.rb, converged on its own by the plugins suite.
#
# The expected plugins are read from the cookbook's attribute files rather than
# duplicated here so that plugin version bumps don't need a matching test change.
attributes_dir = File.expand_path('../../../attributes', __dir__)
expected_plugins = File.read(File.join(attributes_dir, 'plugins.rb'))
                       .scan(/"([^"]+)"\s*=>\s*"([^"]+)"/).to_h
plugins_dir = '/var/lib/jenkins/plugins'
plugin_manager = '/usr/local/jenkins/jars/jenkins-plugin-manager.jar'

# Jenkins is restarted after the plugins are installed, which also expands them
# for the installed version checks below.
describe service 'jenkins' do
  it { should be_running }
end

describe file plugin_manager do
  it { should be_file }
end

describe file '/var/lib/jenkins/plugins.txt' do
  it { should be_file }
  it { should be_owned_by 'jenkins' }
  it { should be_grouped_into 'jenkins' }
  its('mode') { should cmp '0644' }
  its('content.lines.sort') { should eq expected_plugins.map { |name, version| "#{name}:#{version}\n" }.sort }
end

# Jenkins expands each plugin archive into a directory on startup; its manifest
# carries the version that was actually installed. A single command collects
# them all as name:version lines to avoid one round trip per plugin. Manifests
# use CRLF line endings, hence the tr.
installed_versions = command(<<~SH)
  for d in #{plugins_dir}/*/; do
    v=$(sed -n 's/^Plugin-Version: *//p' "${d}META-INF/MANIFEST.MF" | tr -d '\\r')
    echo "$(basename "$d"):$v"
  done
SH

describe installed_versions do
  its('exit_status') { should eq 0 }
  expected_plugins.each do |name, version|
    its('stdout') { should match(/^#{Regexp.escape(name)}:#{Regexp.escape(version)}$/) }
  end
end

# Plugins which are not required are removed: everything the plugin manager
# resolves from plugins.txt, i.e. the listed plugins and their dependencies,
# must be kept and anything else removed. The resolved list is computed the
# same way the recipe does.
resolved_plugins = command(<<~SH).stdout.split
  java -jar #{plugin_manager} \\
    --plugin-download-directory #{plugins_dir} \\
    --plugin-file /var/lib/jenkins/plugins.txt \\
    --latest=false --list --no-download 2>&1 >/dev/null |
  awk '/^All requested plugins:$/{f=1;next} /^$/{f=0} f{print $1}'
SH
installed_plugins = command("ls #{plugins_dir}").stdout.split
                                                .grep(/\.jpi$/).map { |f| f.delete_suffix('.jpi') }

describe 'Installed plugins' do
  subject { installed_plugins.sort }
  it { should eq resolved_plugins.sort }
end

# The plugins suite in kitchen.dokken.yml pre-seeds an unlisted dummy-plugin
# depending on an unlisted dummy-dependency and on the listed structs plugin.
# Both dummies must be removed while structs is kept. The seeding records the
# plugins it left in place, which shows the dummies existed before the converge.
seeded_plugins = %w[dummy-plugin dummy-dependency]

describe file '/root/seeded-jenkins-plugins.txt' do
  it { should exist }
  seeded_plugins.each do |name|
    its('content') { should match(/^#{Regexp.escape(name)}\.jpi$/) }
  end
end

seeded_plugins.each do |name|
  describe file "#{plugins_dir}/#{name}.jpi" do
    it { should_not exist }
  end
end

describe file "#{plugins_dir}/structs.jpi" do
  it { should exist }
end
