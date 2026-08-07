# frozen_string_literal: true

require_relative "lib/mobility_active_storage/version"

Gem::Specification.new do |spec|
  spec.name = "mobility_active_storage"
  spec.version = MobilityActiveStorage::VERSION
  spec.authors = ["Glen Barnes"]
  spec.email = ["barnaclebarnes@mac.com"]

  spec.summary = "Translated Active Storage attachments for Mobility."
  spec.description = <<~DESC
    Adds has_one_translated_attached and has_many_translated_attached to Active Record models,
    letting a single attachment name hold a different file per locale via Mobility. Requires no
    migration: each locale is stored as an ordinary Active Storage attachment whose name carries
    the locale suffix.
  DESC
  spec.homepage = "https://github.com/barnaclebarnes/mobility_active_storage"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ docs/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activestorage", ">= 7.0"
  spec.add_dependency "mobility", ">= 1.2", "< 2.0"
end
