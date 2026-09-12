require 'xcodeproj'
root = File.expand_path('..', __dir__)
ios = File.join(root, 'ios')
project = Xcodeproj::Project.new(File.join(ios, 'Modula.xcodeproj'))
app = project.new_target(:application, 'Modula', :ios, '18.0')
tests = project.new_target(:unit_test_bundle, 'ModulaTests', :ios, '18.0')
ui = project.new_target(:ui_test_bundle, 'ModulaUITests', :ios, '18.0')
[tests, ui].each { |t| t.add_dependency(app) }
[app, tests, ui].each do |target|
  group = project.main_group.new_group(target.name, target.name)
  Dir.glob(File.join(ios, target.name, '**', '*.{swift,m,mm}')).sort.each do |file|
    target.add_file_references([group.new_file(file.delete_prefix(File.join(ios, target.name) + '/'))])
  end
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "digital.modula.app.native#{target == app ? '' : '.' + target.name}"
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'complete'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'NO'
    if target == tests
      config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Modula.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Modula'
      config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    elsif target == ui
      config.build_settings['TEST_TARGET_NAME'] = 'Modula'
    end
  end
end
configuration = project.main_group.new_group('Configuration', 'Configuration')
app.build_configurations.each do |config|
  config.base_configuration_reference = configuration.new_file("#{config.name}.xcconfig")
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(ui)
scheme.set_launch_target(app)
project.save
scheme.save_as(project.path, 'Modula', true)
