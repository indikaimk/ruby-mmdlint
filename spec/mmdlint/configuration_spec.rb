# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mmdlint::Configuration do
  it "has sensible default values" do
    config = described_class.new
    expect(config.node_path).to eq("node")
    expect(config.cli_path).to eq("mmdlint")
    expect(config.mode).to eq(:runner)
    expect(config.timeout).to eq(15)
    expect(config.runner_path).to end_with("runner.mjs")
    expect(config.resolved_working_directory).to eq(Dir.pwd)
  end

  it "allows custom working_directory" do
    config = described_class.new
    config.working_directory = "/custom/path"
    expect(config.resolved_working_directory).to eq("/custom/path")
  end

  it "allows setting custom values via Mmdlint.configure" do
    Mmdlint.configure do |c|
      c.node_path = "/usr/local/bin/node"
      c.timeout = 25
      c.mode = :cli
    end

    expect(Mmdlint.configuration.node_path).to eq("/usr/local/bin/node")
    expect(Mmdlint.configuration.timeout).to eq(25)
    expect(Mmdlint.configuration.mode).to eq(:cli)
  end
end
