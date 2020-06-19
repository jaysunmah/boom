require 'k8s-client'
require_relative '../util/kube_exec'

class PodChaosFactory
  def initialize(chaos_namespace, target_namespace)
    @chaos_namespace = chaos_namespace
    @target_namespace = target_namespace
    @client = K8s::Client.config(K8s::Config.load_file(File.expand_path '~/.kube/config'))
    @kc_exec = KubeExec.new(@client, @target_namespace)
  end
  # GeneratingPodFailureResource.new
  # resource1 = PodFailureResource.new(params).execute
  # resource2 = PodFailureResource.new(params).execute
  def get_resource(name, label_selectors)
    K8s::Resource.new(
        {
            apiVersion: "pingcap.com/v1alpha1",
            kind: "PodChaos",
            metadata: { name: name, namespace: @chaos_namespace },
            spec: {
                action: "pod-failure",
                mode: "one",
                duration: "86400s",
                selector: {
                    namespaces: [@target_namespace],
                    labelSelectors: label_selectors,
                },
                scheduler: { cron: "@every 86401s" }
            }
        }
    )
  end

  def create_resource(name, label_selectors)
    # 1. Create custom k8 resource and apply
    cfg = get_resource(name, label_selectors)
    begin
      # kubectl apply -f ...
      @client.api("pingcap.com/v1alpha1").resource("podchaos", namespace: @chaos_namespace).create_resource(cfg)
    rescue K8s::Error::Conflict
      p "error in creating resource because a resource of the name #{name} already exists, continuing"
    end
    # 2. Validate that fault was properly injected
    until validate_err(name)
      sleep 0.5
    end
  end

  def cleanup(name)
    begin
      chaos = get_podchaos(name)
    rescue K8s::Error::NotFound
      p "No resource with name #{name} found! marking cleanup as success"
      return
    end
    # 1. Get label selector of the injected chaos
    label_selectors = chaos.to_hash.dig(:spec, :selector, :labelSelectors)
    # 2. Get all pods that with the injected chaos' label selectors
    all_pods = get_pods(label_selectors)
    # 3. Get pods affected by fault, and remove those from all pods
    pods_affected = get_affected_pods(name)
    pods_unaffected = all_pods - pods_affected
    # 4. Delete pod resource (if there exists one)
    @client.api("pingcap.com/v1alpha1").resource("podchaos", namespace: @chaos_namespace).delete(name)
    # 5. Make sure that the new pods that have spun up are functional
    until validate_heal(label_selectors, pods_affected, pods_unaffected)
      sleep 0.5
    end
  end

  # verifies that all pods affected by the fault are failing
  def validate_err(name)
    pods_affected = get_affected_pods(name)
    if pods_affected.length == 0
      return false
    end
    # for each pod affected, make sure its completely down
    pods_affected.all? do |p|
      p "Verifying #{p} is failing.."
      begin
        @kc_exec.run(p, "echo foo")
        false
      rescue
        # we should expect it to fail
        true
      end
    end
  end

  # Returns true if the following is satisfied:
  # - # of news pods spun up = # of pods affected
  # - Each of the new pods spun up are healthy
  def validate_heal(label_selectors, pods_affected, pods_unaffected)
    curr_pods = get_pods(label_selectors)
    new_pods = curr_pods - pods_unaffected - pods_affected
    if new_pods.length != pods_affected.length
      return false
    end
    new_pods.all? do |p|
      p "Verifying #{p} is healthy..."
      begin
        logs = @kc_exec.run(p, "echo foo")
        logs.any? {|l| l.include?("foo")}
      rescue
        false
      end
    end
  end

  def get_podchaos(name)
    @client.api("pingcap.com/v1alpha1")
        .resource("podchaos", namespace: @chaos_namespace)
        .get(name)
  end

  def get_affected_pods(name)
    fault = get_podchaos(name)
    resources = fault.dig(:status, :experiment, :podRecords) || []
    resources.map { |r| r.name }
  end

  def get_pods(label_selectors)
    resources = @client.api("v1").resource("pods", namespace: @target_namespace).list(labelSelector: label_selectors)
    resources.map { |r| r.metadata[:name] }
  end

end
