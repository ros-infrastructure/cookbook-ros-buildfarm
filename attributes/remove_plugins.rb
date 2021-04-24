# Plugins on this list will be removed on each chef run.
# Adding plugins to this list requires a minor version bump.
# Removing plugins from this list requires a major version bump.
default['ros_buildfarm']['jenkins']['remove_plugins'] = %w[
  analysis-core
  config-file-provider
  cvs
  icon-shim
]
