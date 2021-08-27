require File.expand_path("../../../../../base", __FILE__)

require Vagrant.source_root.join("plugins/commands/serve/command")
require Vagrant.source_root.join("plugins/commands/serve/broker").to_s

class DummyContext
  attr_reader :metadata
  def initialize(plugin_name)
    @metadata = {"plugin_name" => plugin_name}
  end
end

describe VagrantPlugins::CommandServe::Service::GuestService do
  include_context "unit"

  let(:broker){
    VagrantPlugins::CommandServe::Broker.new(bind: "bind_addr", ports: ["1234"])
  }

  let(:machine){ double("machine") }

  let(:machine_arg){ 
    Hashicorp::Vagrant::Sdk::FuncSpec::Args.new(
      args: [
        Hashicorp::Vagrant::Sdk::FuncSpec::Value.new(
          name: "", 
          type: "hashicorp.vagrant.sdk.Args.Target", 
          value: Google::Protobuf::Any.pack(
            Hashicorp::Vagrant::Sdk::Args::Target.new(stream_id: 1, network: "here:101", target: "unix://here"
        )))
      ]
    )
  }

  subject { described_class.new(broker: broker) }

  before(:each) do
    parent_test_guest = Class.new(Vagrant.plugin("2", :guest)) do
      def detect?(machine)
        true
      end
    end

    test_guest = Class.new(Vagrant.plugin("2", :guest)) do
      def detect?(machine)
        true
      end
    end

    register_plugin do |p|
      p.guest(:parent_test) { parent_test_guest }
      p.guest(:test, :parent_test) { test_guest }
    end
  end

  context "requesting parents" do
    it "generates a spec" do
      spec = subject.parents_spec
      expect(spec).not_to be_nil
    end

    it "raises an error for unknown plugins" do
      ctx = DummyContext.new("idontexisthahaha")
      expect { subject.parents("", ctx) }.to raise_error
    end

    it "requests parents from plugins" do
      ctx = DummyContext.new("test")
      parents = subject.parents("", ctx)
      expect(parents).not_to be_nil
      expect(parents.parents).to include("parent_test")
    end
  end

  context "requesting detect" do
    before do
      test_false_guest = Class.new(Vagrant.plugin("2", :guest)) do
        def detect?(machine)
          false
        end
      end
  
      register_plugin do |p|
        p.guest(:test_false) { test_false_guest }
      end

      VagrantPlugins::CommandServe::Client::Target.any_instance.stub(:project).and_return("")
      VagrantPlugins::CommandServe::Client::Target.any_instance.stub(:name).and_return("dummy")
      VagrantPlugins::CommandServe::Client::Target.any_instance.stub(:provider_name).and_return("virtualbox")
      Vagrant::Environment.any_instance.stub(:machine).and_return(machine)
    end

    it "generates a spec" do
      spec = subject.detect_spec
      expect(spec).not_to be_nil
    end

    it "raises an error for unknown plugins" do
      ctx = DummyContext.new("idontexisthahaha")
      expect { subject.detect("", ctx) }.to raise_error
    end

    it "detects true plugins" do
      ctx = DummyContext.new("test")
      d = subject.detect(machine_arg, ctx)
      expect(d.detected).to be true
    end

    it "detects false plugins" do
      ctx = DummyContext.new("test_false")
      d = subject.detect(machine_arg, ctx)
      expect(d.detected).to be false
    end
  end

  context "requesting has capability" do
    before do
      cap_guest = Class.new(Vagrant.plugin("2", :guest)) do
        def detect?(machine)
          true
        end
      end
  
      register_plugin do |p|
        p.guest(:cap_guest) { cap_guest }
        p.guest_capability(:cap_guest, :mycap) do
          "this is a capability"
        end
      end
    end

    let(:named_cap_request){ 
      Hashicorp::Vagrant::Sdk::FuncSpec::Args.new(
        args: [
          Hashicorp::Vagrant::Sdk::FuncSpec::Value.new(
            name: "", 
            type: "hashicorp.vagrant.sdk.Args.NamedCapability", 
            value: Google::Protobuf::Any.pack(Hashicorp::Vagrant::Sdk::Args::NamedCapability.new(Capability:"mycap")))
        ]
      )
    }

    let(:named_cap_bad_request){ 
      Hashicorp::Vagrant::Sdk::FuncSpec::Args.new(
        args: [
          Hashicorp::Vagrant::Sdk::FuncSpec::Value.new(
            name: "", 
            type: "hashicorp.vagrant.sdk.Args.NamedCapability", 
            value: Google::Protobuf::Any.pack(Hashicorp::Vagrant::Sdk::Args::NamedCapability.new(Capability:"notacapability")))
        ]
      )
    }

    it "generates a spec" do
      spec = subject.has_capability_spec
      expect(spec).not_to be_nil
    end

    it "raises an error for unknown plugins" do
      ctx = DummyContext.new("idontexisthahaha")
      expect { subject.has_capability(test_cap_name, ctx) }.to raise_error
    end

    it "returns true for plugin with capability" do
      ctx = DummyContext.new("cap_guest")
      d = subject.has_capability(named_cap_request, ctx)
      expect(d.has_capability).to be true
    end

    it "returns false for plugin without capability" do
      ctx = DummyContext.new("cap_guest")
      d = subject.has_capability(named_cap_bad_request, ctx)
      expect(d.has_capability).to be false
    end
  end
end
