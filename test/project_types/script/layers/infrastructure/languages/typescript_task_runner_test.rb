
require "project_types/script/test_helper"

describe Script::Layers::Infrastructure::Languages::TypeScriptTaskRunner do
  include TestHelpers::FakeFS

  let(:ctx) { TestHelpers::FakeContext.new }
  let(:script_name) { "foo" }
  let(:language) { "TypeScript" }
  let(:runner) { Script::Layers::Infrastructure::Languages::TypeScriptTaskRunner.new(ctx, script_name) }
  let(:package_json) do
    {
      scripts: {
        build: "javy build/index.js -o build/index.wasm",
      },
    }
  end

  describe ".build" do
    subject { runner.build }

    it "should raise an error if no build script is defined" do
      File.expects(:read).with("package.json").once.returns(JSON.generate(package_json.delete(:scripts)))
      assert_raises(Script::Layers::Infrastructure::Errors::BuildScriptNotFoundError) do
        subject
      end
    end

    it "should raise an error if the build script is not compliant" do
      package_json[:scripts][:build] = ""
      File.expects(:read).with("package.json").once.returns(JSON.generate(package_json))
      assert_raises(Script::Layers::Infrastructure::Errors::InvalidBuildScriptError) do
        subject
      end
    end

    it "should raise an error if the generated web assembly is not found" do
      ctx.write("package.json", JSON.generate(package_json))
      ctx
        .expects(:capture2e)
        .with("npm run build")
        .once
        .returns(["output", mock(success?: true)])

      ctx
        .expects(:capture2e)
        .with("npm run gen-metadata")
        .once
        .returns(["output", mock(success?: true)])

      assert_raises(Script::Layers::Infrastructure::Errors::WebAssemblyBinaryNotFoundError) { subject }
    end

    describe "when index.wasm exists" do
      let(:wasm) { "some compiled code" }
      let(:wasmfile) { "build/index.wasm" }

      before do
        ctx.write("package.json", JSON.generate(package_json))
        ctx.mkdir_p(File.dirname(wasmfile))
        ctx.write(wasmfile, wasm)
      end

      it "triggers the compilation and metadata generation processes" do
        ctx
          .expects(:capture2e)
          .with("npm run build")
          .once
          .returns(["output", mock(success?: true)])

        ctx
          .expects(:capture2e)
          .with("npm run gen-metadata")
          .once
          .returns(["output", mock(success?: true)])

        assert ctx.file_exist?(wasmfile)
        assert_equal wasm, subject
        refute ctx.file_exist?(wasmfile)
      end
    end

    it "should raise error without command output on failure" do
      output = "error_output"
      File.expects(:read).with("package.json").once.returns(JSON.generate(package_json))
      File.expects(:read).never
      ctx
        .stubs(:capture2e)
        .returns([output, mock(success?: false)])

      assert_raises(Script::Layers::Infrastructure::Errors::SystemCallFailureError, output) do
        subject
      end
    end
  end

  describe ".dependencies_installed?" do
    subject { runner.dependencies_installed? }

    before do
      FileUtils.mkdir_p("node_modules")
    end

    it "should return true if node_modules folder exists" do
      assert subject
    end

    it "should return false if node_modules folder does not exists" do
      Dir.stubs(:exist?).returns(false)
      refute subject
    end
  end

  describe ".install_dependencies" do
    subject { runner.install_dependencies }

    describe "when node version is above minimum" do
      it "should install using npm" do
        ctx.expects(:capture2e)
          .with("node", "--version")
          .returns(["v14.15.0", mock(success?: true)])
        ctx.expects(:capture2e)
          .with("npm install --no-audit --no-optional --legacy-peer-deps --loglevel error")
          .returns([nil, mock(success?: true)])
        subject
      end
    end

    describe "when node version is below minimum" do
      it "should raise error" do
        ctx.expects(:capture2e)
          .with("node", "--version")
          .returns(["v14.4.0", mock(success?: true)])

        assert_raises Script::Layers::Infrastructure::Errors::DependencyInstallError do
          subject
        end
      end
    end

    describe "when capture2e fails" do
      it "should raise error" do
        msg = "error message"
        ctx.expects(:capture2e).returns([msg, mock(success?: false)])
        assert_raises Script::Layers::Infrastructure::Errors::DependencyInstallError, msg do
          subject
        end
      end
    end
  end

  describe ".metadata" do
    subject { runner.metadata }

    describe "when metadata file is present and valid" do
      let(:metadata_json) do
        JSON.dump(
          {
            schemaVersions: {
              example: { major: "1", minor: "0" },
            },
          },
        )
      end

      it "should return a proper metadata object" do
        File.expects(:read).with("build/metadata.json").once.returns(metadata_json)

        ctx
          .expects(:file_exist?)
          .with("build/metadata.json")
          .once
          .returns(true)

        assert subject
      end
    end

    describe "when metadata file is missing" do
      it "should raise an exception" do
        assert_raises(Script::Layers::Domain::Errors::MetadataNotFoundError) do
          subject
        end
      end
    end
  end
end