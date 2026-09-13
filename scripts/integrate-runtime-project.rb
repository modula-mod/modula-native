require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'ios/Modula.xcodeproj'))
app = project.targets.find { |t| t.name == 'Modula' }
group = project.main_group.groups.find { |g| g.name == 'Modula' }
existing = app.source_build_phase.files_references.map { |r| r.real_path.to_s }
Dir.glob(File.join(root, 'ios/Modula/**/*.{swift,m,mm}')).sort.each do |file|
  app.add_file_references([group.new_file(file.delete_prefix(File.join(root, 'ios/Modula/') ))]) unless existing.include?(file)
end
resources = project.main_group.groups.find { |g| g.name == 'Runtime resources' } || project.main_group.new_group('Runtime resources')
manifest = resources.files.find { |f| f.path.end_with?('manifests.json') } || resources.new_file('../runtime/src/registry/manifests.json')
app.resources_build_phase.add_file_reference(manifest, true)
phase = app.shell_script_build_phases.find { |p| p.name == 'Bundle module runtime' } || app.new_shell_script_build_phase('Bundle module runtime')
phase.shell_script = '"$SRCROOT/../scripts/bundle-runtime.sh"'
phase.always_out_of_date = '1'
app.build_configurations.each do |c|
  c.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++20'
  c.build_settings['HEADER_SEARCH_PATHS'] = ['$(inherited)', '$(SRCROOT)/build/generated/ios']
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  c.build_settings['INFOPLIST_FILE'] = 'Modula/Info.plist'
end
project.targets.each do |target|
  target.build_configurations.each do |c|
    c.build_settings.delete('OTHER_LDFLAGS')
    c.build_settings['ENABLE_APP_INTENTS_METADATA_EXTRACTION'] = 'NO'
  end
end
project.save
