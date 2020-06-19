require 'concurrent'
require "bundler/setup"
require "dry/cli"
require_relative '../chaos-mesh/pod_chaos_factory'

class PodFailure
  include Concurrent::Async
  def initialize(chaos_namespace, target_namespace)
    @factory = PodChaosFactory.new(chaos_namespace, target_namespace)
  end

  def async_create(name, label_selectors)
    async.create(name, label_selectors)
  end

  def async_heal(label)
    async.heal(label)
  end

  # Creates pod failure with name `name` on all pods that apply to
  # `label_selectors`
  # Ensures that the pod failure has successfully been injected before returning
  def create(name, label_selectors)
    @factory.create_resource(name, label_selectors)
  end

  # Heals pod failure with name `name`
  # Ensures all pods affected by the removed pod failure have recovered before returning
  def heal(name)
    @factory.cleanup(name)
  end
end

module Foo
  module CLI
    module Commands
      extend Dry::CLI::Registry

      class Create < Dry::CLI::Command
        argument :chaos_namespace, required: true, desc: "namespace to create chaos resource"
        argument :target_namespace, required: true, desc: "namespace of target resource"
        argument :name, required: true, desc: "name of pod failure resource"
        argument :selector, required: true, desc: "labelSelectors to identify target"
        def call(chaos_namespace:, target_namespace:, name:, selector:, **)
          label_selectors = Hash[selector.split(",").collect { |elem| [elem.split("=")[0], elem.split("=")[1]] }]
          pf = PodFailure.new(chaos_namespace, target_namespace)
          pf.create(name, label_selectors)
        end
      end

      class Heal < Dry::CLI::Command
        argument :chaos_namespace, required: true, desc: "namespace to create chaos resource"
        argument :target_namespace, required: true, desc: "namespace of target resource"
        argument :name, required: true, desc: "name of pod failure resource"
        def call(chaos_namespace:, target_namespace:, name:, **)
          pf = PodFailure.new(chaos_namespace, target_namespace)
          pf.heal(name)
        end
      end

      register "create", Create
      register "heal", Heal
    end
  end
end

Dry::CLI.new(Foo::CLI::Commands).call

