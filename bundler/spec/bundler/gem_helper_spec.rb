# frozen_string_literal: true

require "rake"
require "bundler/gem_helper"

RSpec.describe Bundler::GemHelper do
  let(:app_name) { "lorem__ipsum" }
  let(:app_path) { bundled_app app_name }
  let(:app_gemspec_path) { app_path.join("#{app_name}.gemspec") }

  before(:each) do
    global_config "BUNDLE_GEM__MIT" => "false", "BUNDLE_GEM__TEST" => "false", "BUNDLE_GEM__COC" => "false", "BUNDLE_GEM__LINTER" => "false",
                  "BUNDLE_GEM__CI" => "false", "BUNDLE_GEM__CHANGELOG" => "false"
    bundle "gem #{app_name}"
    prepare_gemspec(app_gemspec_path)
  end

  context "determining gemspec" do
    subject { Bundler::GemHelper.new(app_path) }

    context "fails" do
      it "when there is no gemspec" do
        FileUtils.rm app_gemspec_path
        expect { subject }.to raise_error(/Unable to determine name/)
      end

      it "when there are two gemspecs and the name isn't specified" do
        FileUtils.touch app_path.join("#{app_name}-2.gemspec")
        expect { subject }.to raise_error(/Unable to determine name/)
      end
    end

    context "interpolates the name" do
      it "when there is only one gemspec" do
        expect(subject.gemspec.name).to eq(app_name)
      end

      it "for a hidden gemspec" do
        FileUtils.mv app_gemspec_path, app_path.join(".gemspec")
        expect(subject.gemspec.name).to eq(app_name)
      end
    end

    it "handles namespaces and converts them to CamelCase" do
      bundle "gem #{app_name}-foo_bar"
      underscore_path = bundled_app "#{app_name}-foo_bar"

      lib = underscore_path.join("lib/#{app_name}/foo_bar.rb").read
      expect(lib).to include("module LoremIpsum")
      expect(lib).to include("module FooBar")
    end
  end

  context "gem management" do
    def mock_confirm_message(message)
      expect(Bundler.ui).to receive(:confirm).with(message)
    end

    def mock_build_message(name, version)
      message = "#{name} #{version} built to pkg/#{name}-#{version}.gem."
      mock_confirm_message message
    end

    def mock_checksum_message(name, version)
      message = "#{name} #{version} checksum written to checksums/#{name}-#{version}.gem.sha512."
      mock_confirm_message message
    end

    subject! { Bundler::GemHelper.new(app_path) }
    let(:app_version) { "0.1.0" }
    let(:app_gem_dir) { app_path.join("pkg") }
    let(:app_gem_path) { app_gem_dir.join("#{app_name}-#{app_version}.gem") }
    let(:app_sha_path) { app_path.join("checksums", "#{app_name}-#{app_version}.gem.sha512") }
    let(:app_gemspec_content) { File.read(app_gemspec_path) }

    before(:each) do
      content = app_gemspec_content.gsub("TODO: ", "")
      content.sub!(/homepage\s+= ".*"/, 'homepage = ""')
      content.gsub!(/spec\.metadata.+\n/, "")
      File.open(app_gemspec_path, "w") {|file| file << content }
    end

    it "uses a shell UI for output" do
      expect(Bundler.ui).to be_a(Bundler::UI::Shell)
    end

    describe "#install" do
      let!(:rake_application) { Rake.application }

      before(:each) do
        Rake.application = Rake::Application.new
      end

      after(:each) do
        Rake.application = rake_application
      end

      context "defines Rake tasks" do
        let(:task_names) do
          %w[build install release release:guard_clean
             release:source_control_push release:rubygem_push]
        end

        context "before installation" do
          it "raises an error with appropriate message" do
            task_names.each do |name|
              skip "Rake::FileTask '#{name}' exists" if File.exist?(name)
              expect { Rake.application[name] }.
                to raise_error(/^Don't know how to build task '#{name}'/)
            end
          end
        end

        context "after installation" do
          before do
            subject.install
          end

          it "adds Rake tasks successfully" do
            task_names.each do |name|
              expect { Rake.application[name] }.not_to raise_error
              expect(Rake.application[name]).to be_instance_of Rake::Task
            end
          end

          it "provides a way to access the gemspec object" do
            expect(subject.gemspec.name).to eq(app_name)
          end
        end
      end
    end

    describe "#build_gem" do
      context "when build failed" do
        it "raises an error with appropriate message" do
          # break the gemspec by adding back the TODOs
          File.open(app_gemspec_path, "w") {|file| file << app_gemspec_content }
          expect { subject.build_gem }.to raise_error(/TODO/)
        end
      end

      context "when build was successful" do
        it "creates .gem file" do
          mock_build_message app_name, app_version
          subject.build_gem
          expect(app_gem_path).to exist
        end
      end

      context "when building in the current working directory" do
        it "creates .gem file" do
          mock_build_message app_name, app_version
          Dir.chdir app_path do
            Bundler::GemHelper.new.build_gem
          end
          expect(app_gem_path).to exist
        end
      end

      context "when building in a location relative to the current working directory" do
        it "creates .gem file" do
          mock_build_message app_name, app_version
          Dir.chdir File.dirname(app_path) do
            Bundler::GemHelper.new(File.basename(app_path)).build_gem
          end
          expect(app_gem_path).to exist
        end
      end
    end

    describe "#build_checksum" do
      context "when build was successful" do
        it "creates .sha512 file" do
          mock_build_message app_name, app_version
          mock_checksum_message app_name, app_version
          subject.build_checksum
          expect(app_sha_path).to exist
        end
      end
      context "when building in the current working directory" do
        it "creates a .sha512 file" do
          mock_build_message app_name, app_version
          mock_checksum_message app_name, app_version
          Dir.chdir app_path do
            Bundler::GemHelper.new.build_checksum
          end
          expect(app_sha_path).to exist
        end
      end
      context "when building in a location relative to the current working directory" do
        it "creates a .sha512 file" do
          mock_build_message app_name, app_version
          mock_checksum_message app_name, app_version
          Dir.chdir File.dirname(app_path) do
            Bundler::GemHelper.new(File.basename(app_path)).build_checksum
          end
          expect(app_sha_path).to exist
        end
      end
    end

    describe "#install_gem" do
      context "when installation was successful" do
        it "gem is installed" do
          mock_build_message app_name, app_version
          mock_confirm_message "#{app_name} (#{app_version}) installed."
          subject.install_gem(nil, :local)
          expect(app_gem_path).to exist
          gem_command :list
          expect(out).to include("#{app_name} (#{app_version})")
        end
      end

      context "when installation fails" do
        it "raises an error with appropriate message" do
          # create empty gem file in order to simulate install failure
          allow(subject).to receive(:build_gem) do
            FileUtils.mkdir_p(app_gem_dir)
            FileUtils.touch app_gem_path
            app_gem_path
          end
          expect { subject.install_gem }.to raise_error(/Running `#{gem_bin} install #{app_gem_path}` failed/)
        end
      end
    end

    describe "rake release" do
      let!(:rake_application) { Rake.application }

      before(:each) do
        Rake.application = Rake::Application.new
        subject.install
      end

      after(:each) do
        Rake.application = rake_application
      end

      before do
        git("init", :dir => app_path)
        git("config user.email \"you@example.com\"", :dir => app_path)
        git("config user.name \"name\"", :dir => app_path)
        git("config commit.gpgsign false", :dir => app_path)
        git("config push.default simple", :dir => app_path)

        # silence messages
        allow(Bundler.ui).to receive(:confirm)
        allow(Bundler.ui).to receive(:error)
      end

      context "fails" do
        it "when there are unstaged files" do
          expect { Rake.application["release"].invoke }.
            to raise_error("There are files that need to be committed first.")
        end

        it "when there are uncommitted files" do
          git("add .", :dir => app_path)
          expect { Rake.application["release"].invoke }.
            to raise_error("There are files that need to be committed first.")
        end

        it "when there is no git remote" do
          git("commit -a -m \"initial commit\"", :dir => app_path)
          expect { Rake.application["release"].invoke }.to raise_error(RuntimeError)
        end
      end

      context "succeeds" do
        let(:repo) { build_git("foo", :bare => true) }

        before do
          git("remote add origin #{file_uri_for(repo.path)}", :dir => app_path)
          git('commit -a -m "initial commit"', :dir => app_path)
        end

        context "on releasing" do
          before do
            mock_build_message app_name, app_version
            mock_confirm_message "Tagged v#{app_version}."
            mock_confirm_message "Pushed git commits and release tag."

            git("push -u origin master", :dir => app_path)
          end

          it "calls rubygem_push with proper arguments" do
            expect(subject).to receive(:rubygem_push).with(app_gem_path.to_s)

            Rake.application["release"].invoke
          end

          it "uses Kernel.system" do
            cmd = gem_bin.shellsplit
            expect(Kernel).to receive(:system).with(*cmd, "push", app_gem_path.to_s, "--host", "http://example.org").and_return(true)

            Rake.application["release"].invoke
          end

          it "also works when releasing from an ambiguous reference" do
            # Create a branch with the same name as the tag
            git("checkout -b v#{app_version}", :dir => app_path)
            git("push -u origin v#{app_version}", :dir => app_path)

            expect(subject).to receive(:rubygem_push).with(app_gem_path.to_s)

            Rake.application["release"].invoke
          end

          it "also works with releasing from a branch not yet pushed" do
            git("checkout -b module_function", :dir => app_path)

            expect(subject).to receive(:rubygem_push).with(app_gem_path.to_s)

            Rake.application["release"].invoke
          end
        end

        context "on releasing with a custom tag prefix" do
          before do
            Bundler::GemHelper.tag_prefix = "foo-"
            mock_build_message app_name, app_version
            mock_confirm_message "Pushed git commits and release tag."

            git("push -u origin master", :dir => app_path)
            expect(subject).to receive(:rubygem_push).with(app_gem_path.to_s)
          end

          it "prepends the custom prefix to the tag" do
            mock_confirm_message "Tagged foo-v#{app_version}."

            Rake.application["release"].invoke
          end
        end

        it "even if tag already exists" do
          mock_build_message app_name, app_version
          mock_confirm_message "Tag v#{app_version} has already been created."
          expect(subject).to receive(:rubygem_push).with(app_gem_path.to_s)

          git("tag -a -m \"Version #{app_version}\" v#{app_version}", :dir => app_path)

          Rake.application["release"].invoke
        end
      end
    end

    describe "release:rubygem_push" do
      let!(:rake_application) { Rake.application }

      before(:each) do
        Rake.application = Rake::Application.new
        subject.install
        allow(subject).to receive(:sh_with_input)
      end

      after(:each) do
        Rake.application = rake_application
      end

      before do
        git("init", :dir => app_path)
        git("config user.email \"you@example.com\"", :dir => app_path)
        git("config user.name \"name\"", :dir => app_path)
        git("config push.gpgsign simple", :dir => app_path)

        # silence messages
        allow(Bundler.ui).to receive(:confirm)
        allow(Bundler.ui).to receive(:error)

        credentials = double("credentials", "file?" => true)
        allow(Bundler.user_home).to receive(:join).
          with(".gem/credentials").and_return(credentials)
      end

      describe "success messaging" do
        context "No allowed_push_host set" do
          before do
            allow(subject).to receive(:allowed_push_host).and_return(nil)
          end

          around do |example|
            orig_host = ENV["RUBYGEMS_HOST"]
            ENV["RUBYGEMS_HOST"] = rubygems_host_env

            example.run

            ENV["RUBYGEMS_HOST"] = orig_host
          end

          context "RUBYGEMS_HOST env var is set" do
            let(:rubygems_host_env) { "https://custom.env.gemhost.com" }

            it "should report successful push to the host from the environment" do
              mock_confirm_message "Pushed #{app_name} #{app_version} to #{rubygems_host_env}"

              Rake.application["release:rubygem_push"].invoke
            end
          end

          context "RUBYGEMS_HOST env var is not set" do
            let(:rubygems_host_env) { nil }

            it "should report successful push to rubygems.org" do
              mock_confirm_message "Pushed #{app_name} #{app_version} to rubygems.org"

              Rake.application["release:rubygem_push"].invoke
            end
          end

          context "RUBYGEMS_HOST env var is an empty string" do
            let(:rubygems_host_env) { "" }

            it "should report successful push to rubygems.org" do
              mock_confirm_message "Pushed #{app_name} #{app_version} to rubygems.org"

              Rake.application["release:rubygem_push"].invoke
            end
          end
        end

        context "allowed_push_host set in gemspec" do
          before do
            allow(subject).to receive(:allowed_push_host).and_return("https://my.gemhost.com")
          end

          it "should report successful push to the allowed gem host" do
            mock_confirm_message "Pushed #{app_name} #{app_version} to https://my.gemhost.com"

            Rake.application["release:rubygem_push"].invoke
          end
        end
      end
    end
  end
end
