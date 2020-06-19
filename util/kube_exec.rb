require 'faye/websocket'
require 'eventmachine'

class KubeExec
  def initialize(client, namespace)
    t = client.instance_variable_get('@transport')
    opts = t.instance_variable_get('@options')
    @namespace=namespace
    @host =  t.instance_variable_get('@server').sub('https://', '')
    @cert_file=opts[:client_cert]
    @key_file=opts[:client_key]
  end

  def run(pod, cmd)
    logs = []
    cmd_str = cmd.split.map { |s| "command=" + s}.join("&")
    url = "wss://#{@host}/api/v1/namespaces/#{@namespace}/pods/#{pod}/exec?#{cmd_str}&stderr=true&stdout=true"
    err = nil
    EM.run {
      ws = Faye::WebSocket::Client.new(
          url,
          [],
          {
              :tls => {
                  :cert_chain_file => @cert_file,
                  :private_key_file => @key_file,
              }
          }
      )

      ws.on :error do |event|
        err = event.instance_variable_get('@message')
      end

      ws.on :message do |event|
        logs.push(event.data.pack('c*'))
      end

      ws.on :close do |event|
        ws = nil
        EventMachine::stop_event_loop
      end
    }
    if err != nil
      raise "Unable to execute log: #{err}"
    end
    logs
  end
end
