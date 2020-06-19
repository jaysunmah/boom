require_relative 'primitives/pod_failure'

pf = PodFailure.new("chaos-testing", "vitess")
label_selectors = {
    :app => "vitess",
    :component => "vtgate",
}
chaosname = "test-pod-failure"

t = pf.async_create(chaosname, label_selectors)
res = t.wait
p res.reason
# pf.create()

sleep 5

t = pf.async_heal(chaosname)
p t.wait.value


