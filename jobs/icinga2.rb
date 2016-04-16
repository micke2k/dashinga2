
#/******************************************************************************
# * Icinga 2 Dashing Job                                                       *
# * Copyright (C) 2015 Icinga Development Team (https://www.icinga.org)        *
# *                                                                            *
# * This program is free software; you can redistribute it and/or              *
# * modify it under the terms of the GNU General Public License                *
# * as published by the Free Software Foundation; either version 2             *
# * of the License, or (at your option) any later version.                     *
# *                                                                            *
# * This program is distributed in the hope that it will be useful,            *
# * but WITHOUT ANY WARRANTY; without even the implied warranty of             *
# * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
# * GNU General Public License for more details.                               *
# *                                                                            *
# * You should have received a copy of the GNU General Public License          *
# * along with this program; if not, write to the Free Software Foundation     *
# * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.             *
# ******************************************************************************/

require 'rest_client'



$node_name = Socket.gethostbyname(Socket.gethostname).first
if defined? settings.icinga2_api_nodename
  node_name = settings.icinga2_api_nodename
end
#$api_url_base = "https://192.168.99.100:4665"
$api_url_base = "https://localhost:5665"
if defined? settings.icinga2_api_url
  api_url_base = settings.icinga2_api_url
end
$api_username = "root"
if defined? settings.icinga2_api_username
  api_username = settings.icinga2_api_username
end
$api_password = "root"
if defined? settings.icinga2_api_password
  api_password = settings.icinga2_api_password
end

# prepare the rest client ssl stuff
def prepare_rest_client(api_url)
  # check whether pki files are there, otherwise use basic auth
  if File.file?("pki/" + $node_name + ".crt")
    puts "PKI found, using client certificates for connection to Icinga 2 API"
    cert_file = File.read("pki/" + $node_name + ".crt")
    key_file = File.read("pki/" + $node_name + ".key")
    ca_file = File.read("pki/ca.crt")

    cert = OpenSSL::X509::Certificate.new(cert_file)
    key = OpenSSL::PKey::RSA.new(key_file)

    options = {:ssl_client_cert => cert, :ssl_client_key => key, :ssl_ca_file => ca_file, :verify_ssl => OpenSSL::SSL::VERIFY_NONE}
  else
 

    options = { :user => $api_username, :password => $api_password, :verify_ssl => OpenSSL::SSL::VERIFY_NONE }
  end

  res = RestClient::Resource.new(URI.encode(api_url), options)
  return res
end

def get_stats()
  api_url = $api_url_base + "/v1/status/CIB"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}

  return rest_client.get(headers)
end

def get_app()
  api_url = $api_url_base + "/v1/status/IcingaApplication"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}

  return rest_client.get(headers)
end

def get_serv()
  api_url = $api_url_base + "/v1/objects/services?attrs=display_name&attrs=state&attrs=last_state_change&attrs=host_name&filter=service.state!=0"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}

  return rest_client.get(headers)
end

def get_hosts()
  api_url = $api_url_base + "/v1/objects/hosts?attrs=display_name&attrs=state&attrs=groups&attrs=last_state_change&filter=host.state!=0"
  rest_client = prepare_rest_client(api_url)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}

  return rest_client.get(headers)
end

SCHEDULER.every '5s' , allow_overlapping: false do


     

  total_critical = 0
  total_warning = 0
  total_ack = 0
  total = 0

  app = get_app()
  result = JSON.parse(app.body)
  icingaapplication = result["results"][0] # there's only one row
  app_info = icingaapplication["status"]

 # puts "App Info: " + app_info.to_s

  version = app_info["icingaapplication"]["app"]["version"]

  res = get_stats()
  result = JSON.parse(res.body)
  cib = result["results"][0] # there's only one row
  status = cib["status"]

 # puts "Status: " + status.to_s

  uptime = status["uptime"].round
  uptime = Time.at(uptime).utc.strftime("%H:%M:%S")
  avg_latency = status["avg_latency"].round(2)
  avg_execution_time = status["avg_execution_time"].round(2)

  services_ok = status["num_services_ok"].to_int
  services_warning = status["num_services_warning"].to_int
  services_critical = status["num_services_critical"].to_int
  services_unknown = status["num_services_unknown"].to_int
  services_ack = status["num_services_acknowledged"].to_int
  services_downtime = status["num_services_in_downtime"].to_int

  hosts_up = status["num_hosts_up"].to_int
  hosts_down = status["num_hosts_down"].to_int
  hosts_ack = status["num_hosts_acknowledged"].to_int
  hosts_downtime = status["num_hosts_in_downtime"].to_int

  total_critical = services_critical + hosts_down
  total_warning = services_warning

    if hosts_down > 0 then
    color2 = 'red'
    else
    color2 = 'blue'
   	end
	
	if services_critical > 0 then
    color3 = 'red'
    else
    color3 = 'blue'
   	end
	
	if services_warning > 0 then
    color4 = 'yellow'
    else
    color4 = 'blue'
   	end
  
  if total_critical > 0 then
    color = 'red'
    value = total_critical.to_s
  elsif total_warning > 0 then
    color = 'yellow'
    value = total_warning.to_s
  else
    color = 'blue'
    value = total.to_s
  end

  # events
  send_event('icinga-overview', {
   value: value,
   color: color })

  send_event('icinga-version', {
   value: version.to_s,
   color: 'blue' })

  send_event('icinga-uptime', {
   value: uptime.to_s,
   color: 'blue' })

  send_event('icinga-latency', {
   value: avg_latency.to_s + "s",
   color: 'blue' })

  send_event('icinga-execution-time', {
   value: avg_execution_time.to_s,
   color: 'blue' })

  # down, critical, warning
  send_event('icinga-host-down', {
   value: hosts_down.to_s,
   color: color2 })

  send_event('icinga-service-critical', {
   value: services_critical.to_s,
   color: color3 })

  send_event('icinga-service-warning', {
   value: services_warning.to_s,
   color: color4 })

  # ack, downtime
  send_event('icinga-service-ack', {
   value: services_ack.to_s,
   color: 'blue' })

  send_event('icinga-host-ack', {
   value: hosts_ack.to_s,
   color: 'blue' })

  send_event('icinga-service-downtime', {
   value: services_downtime.to_s,
   color: 'orange' })

  send_event('icinga-host-downtime', {
   value: hosts_downtime.to_s,
   color: 'orange' })
   



end


SCHEDULER.every '10s', allow_overlapping: false do

 #Get Services with status Unknown, Warning or Critical
 #Example:
 
=begin

curl -k -s -u root:root 'https://localhost:5665/v1/objects/hosts?attrs=display_name&attrs=state&attrs=groups&attrs=last_state_change' |  python -m json.tool
{
    "results": [
        {
            "attrs": {
                "display_name": "RTR1",
                "groups": [
                    "firewalls"
                ],
                "last_state_change": 1460070654.744015,
                "state": 1.0
            },
            "joins": {},
            "meta": {},
            "name": "RTR1",
            "type": "Host"
        },
        {
            "attrs": {
                "display_name": "RTR2",
                "groups": [
                    "firewalls"
                ],
                "last_state_change": 1460068958.757517,
                "state": 0.0
            },
            "joins": {},
            "meta": {},
            "name": "RTR2",
            "type": "Host"
        },
        {
            "attrs": {
                "display_name": "icinga.local",
                "groups": [],
                "last_state_change": 1459936283.216255,
                "state": 0.0
            },
            "joins": {},
            "meta": {},
            "name": "icinga.local",
            "type": "Host"
        }
    ]
}


=end
 
 #fetch and parse 'em
 serv = get_serv()
 data = JSON.parse(serv.body, :symbolize_names => true)
 
 #create array for storing
 icinga2array = Array.new

 #loop through the results under => "attrs": and store them in array
data[:results].each do |element|
	element[:attrs].each do |element2,element3|
	     icinga2array << element3	   
	end
 end
 
 #create individual arrays for each item
	icinga2time = Array.new
	icinga2hosts = Array.new
	icinga2services = Array.new
    icinga2state = Array.new
	icinga2time2 = Array.new

 #loop through icinga2array and create 4 new arrays that store values individually (hosts, service etc..)
 
 host=1
 service=0
 state_time=2
 state=3
 
 icinga2array.each do |key|
 host_name = icinga2array[host]
 services = icinga2array[service]
 state_times = icinga2array[state_time]
 states = icinga2array[state]
  
  	icinga2hosts << host_name
	icinga2services << services
	icinga2time << state_times
	icinga2state << states
		
 host+=4
 service+=4
 state_time+=4
 state+=4
end

#remove nil values
icinga2hosts.compact!
icinga2services.compact!
icinga2time.compact!
icinga2state.compact!
#remove decimals
round_down = Proc.new { |number| number.floor }
icinga2time = icinga2time.collect(&round_down)

#save time as currentime - epoch. change format to display H:M:S
timei=0
icinga2time.each do |key|
	time2 = Time.now.to_i - icinga2time[timei]
	time3 = Time.at(time2).utc.strftime("%H:%M:%S")
		
	icinga2time2 << time3
	timei+=1
end
	
	
icinga2state2=Array.new	
icinga2state.each do |key|
	if key == 2.0
	key = "Critical"
	icinga2state2 <<key
	elsif key == 3.0
	key = "Unkown/Timeout"
	icinga2state2 <<key
	elsif key == 1.0
	key = "Warning"
	icinga2state2 <<key
	end
end



rows = [
  { cols: [ {value: icinga2hosts[0]}, {value: icinga2services[0]}, {value: icinga2time2[0]}, {value: icinga2state2[0]} ]},
  { cols: [ {value: icinga2hosts[1]}, {value: icinga2services[1]}, {value: icinga2time2[1]}, {value: icinga2state2[1]} ]},
  { cols: [ {value: icinga2hosts[2]}, {value: icinga2services[2]}, {value: icinga2time2[2]}, {value: icinga2state2[2]} ]},
  { cols: [ {value: icinga2hosts[3]}, {value: icinga2services[3]}, {value: icinga2time2[3]}, {value: icinga2state2[3]} ]},
  { cols: [ {value: icinga2hosts[4]}, {value: icinga2services[4]}, {value: icinga2time2[4]}, {value: icinga2state2[4]} ]},
  { cols: [ {value: icinga2hosts[5]}, {value: icinga2services[5]}, {value: icinga2time2[5]}, {value: icinga2state2[5]} ]},
  { cols: [ {value: icinga2hosts[6]}, {value: icinga2services[6]}, {value: icinga2time2[6]}, {value: icinga2state2[6]} ]},
  { cols: [ {value: icinga2hosts[7]}, {value: icinga2services[7]}, {value: icinga2time2[7]}, {value: icinga2state2[7]} ]},
  { cols: [ {value: icinga2hosts[8]}, {value: icinga2services[8]}, {value: icinga2time2[8]}, {value: icinga2state2[8]} ]},
  { cols: [ {value: icinga2hosts[9]}, {value: icinga2services[9]}, {value: icinga2time2[9]}, {value: icinga2state2[9]} ]}
 
]

send_event('serviceproblems', {  rows: rows } ) 

end

SCHEDULER.every '10s' , allow_overlapping: false do

 #Get Hosts with status Down
 #Example:
 
=begin

 curl -k -s -u root:root 'https://localhost:5665/v1/objects/hosts?attrs=display_name&attrs=state&attrs=groups&attrs=last_state_change&filter=host.state!=0' |  python -m json.tool
{
    "results": [
        {
            "attrs": {
                "display_name": "RTR1",
                "groups": [
                    "firewalls"
                ],
                "last_state_change": 1460070654.744015,
                "state": 1.0
            },
            "joins": {},
            "meta": {},
            "name": "RTR1",
            "type": "Host"
        },
        {
            "attrs": {
                "display_name": "RTR2",
                "groups": [
                    "firewalls"
                ],
                "last_state_change": 1460071189.745863,
                "state": 1.0
            },
            "joins": {},
            "meta": {},
            "name": "RTR2",
            "type": "Host"
        }
    ]
}



=end
 
 #fetch and parse 'em
 hostserv = get_hosts()
 hostdata = JSON.parse(hostserv.body, :symbolize_names => true)
 
 #create array for storing
 icinga2hostarray = Array.new

 #loop through the results under => "attrs": and store them in array
hostdata[:results].each do |element|
	element[:attrs].each do |element2,element3|
	     icinga2hostarray << element3	   
	end
 end
 
 #create individual arrays for each item
	icinga2hosttime = Array.new
	icinga2hostname = Array.new
	icinga2hostgroup = Array.new
    icinga2hoststate = Array.new
	icinga2hosttime2 = Array.new

 ###loop through icinga2array and create 4 new arrays that store values individually (hosts, service etc..)
 
 #set initial iteration values
 hostgroup=0
 hostname=1
 hoststate_time=2
 hoststate=3
 
 #loop for each entry and split into variables
 icinga2hostarray.each do |key|
 hosthost_name = icinga2hostarray[hostgroup]
 hostgroups = icinga2hostarray[hostname]
 hoststate_times = icinga2hostarray[hoststate_time]
 hoststates = icinga2hostarray[hoststate]
 
 #if no hostgroup display No Group 
  if hostgroups == []
	hostgroups = "No Group"
  end
  
 # add to arrays
  	icinga2hostname << hosthost_name
	icinga2hostgroup << hostgroups
	icinga2hosttime << hoststate_times
	icinga2hoststate << hoststates
	
 #increase count by number of items in the array		
 hostname+=4
 hostgroup+=4
 hoststate_time+=4
 hoststate+=4
end

#remove nil values
icinga2hostname.compact!
icinga2hostgroup.flatten!
icinga2hostgroup.compact!
icinga2hosttime.compact!
icinga2hoststate.compact!

#remove decimals
round_down = Proc.new { |number| number.floor }
icinga2hosttime = icinga2hosttime.collect(&round_down)

#save time as currentime - time since the state changed. change format to display H:M:S
timei=0
icinga2hosttime.each do |key|
	time2 = Time.now.to_i - icinga2hosttime[timei]
	time3 = Time.at(time2).utc.strftime("%H:%M:%S")
		
	icinga2hosttime2 << time3
	timei+=1
end
	
	
icinga2hoststate2=Array.new	
icinga2hoststate.each do |key|
	if key == 0.0
	key = "UP"
	icinga2hoststate2 <<key
	elsif key == 1.0
	key = "DOWN"
	icinga2hoststate2 <<key
	end
end

rows = [
  { cols: [ {value: icinga2hostname[0]}, {value: icinga2hostgroup[0]}, {value: icinga2hosttime2[0]}, {value: icinga2hoststate2[0]} ]},
  { cols: [ {value: icinga2hostname[1]}, {value: icinga2hostgroup[1]}, {value: icinga2hosttime2[1]}, {value: icinga2hoststate2[1]} ]},
  { cols: [ {value: icinga2hostname[2]}, {value: icinga2hostgroup[2]}, {value: icinga2hosttime2[2]}, {value: icinga2hoststate2[2]} ]},
  { cols: [ {value: icinga2hostname[3]}, {value: icinga2hostgroup[3]}, {value: icinga2hosttime2[3]}, {value: icinga2hoststate2[3]} ]},
  { cols: [ {value: icinga2hostname[4]}, {value: icinga2hostgroup[4]}, {value: icinga2hosttime2[4]}, {value: icinga2hoststate2[4]} ]},
  { cols: [ {value: icinga2hostname[5]}, {value: icinga2hostgroup[5]}, {value: icinga2hosttime2[5]}, {value: icinga2hoststate2[5]} ]},
  { cols: [ {value: icinga2hostname[6]}, {value: icinga2hostgroup[6]}, {value: icinga2hosttime2[6]}, {value: icinga2hoststate2[6]} ]},
  { cols: [ {value: icinga2hostname[7]}, {value: icinga2hostgroup[7]}, {value: icinga2hosttime2[7]}, {value: icinga2hoststate2[7]} ]},
  { cols: [ {value: icinga2hostname[8]}, {value: icinga2hostgroup[8]}, {value: icinga2hosttime2[8]}, {value: icinga2hoststate2[8]} ]},
  { cols: [ {value: icinga2hostname[9]}, {value: icinga2hostgroup[9]}, {value: icinga2hosttime2[9]}, {value: icinga2hoststate2[9]} ]}
 
]

send_event('hostproblems', {  rows: rows } ) 

end


SCHEDULER.every '10.1s', allow_overlapping: false do

random=rand(10000000)

send_event('logo', {  image: "http://192.168.200.40/cacti/plugins/weathermap/output/11.png?" + random.to_s } ) 

end

#Oxidized
=begin
Example:
curl -k -s -u root:root 'https://192.168.200.50/oxidized/nodes/stats.json' |  python -m json.tool
{
    "192.168.200.2": {
        "success": [
            {
                "end": "2016-04-15 16:12:54 UTC",
                "start": "2016-04-15 16:12:50 UTC",
                "time": 3.540481275
            },
            {
                "end": "2016-04-15 16:13:25 UTC",
                "start": "2016-04-15 16:13:21 UTC",
                "time": 3.461459511
            },
            {
                "end": "2016-04-15 16:13:50 UTC",
                "start": "2016-04-15 16:13:46 UTC",
                "time": 3.313887955
            }
        ]
    },
    "192.168.206.30": {
        "success": [
            {
                "end": "2016-04-15 16:12:50 UTC",
                "start": "2016-04-15 16:12:49 UTC",
                "time": 0.786971799
            },
            {
                "end": "2016-04-15 16:13:21 UTC",
                "start": "2016-04-15 16:13:20 UTC",
                "time": 0.588055992
            },
            {
                "end": "2016-04-15 16:13:42 UTC",
                "start": "2016-04-15 16:13:41 UTC",
                "time": 0.974374826
            }
        ]
    },
    "192.168.206.31": {
        "no_connection": [
            {
                "end": "2016-04-15 16:13:20 UTC",
                "start": "2016-04-15 16:12:54 UTC",
                "time": 25.284773792
            },
            {
                "end": "2016-04-15 16:13:46 UTC",
                "start": "2016-04-15 16:13:20 UTC",
                "time": 25.289347616
            }
        ]
    }
}

=end

$api_url_base_oxidized = "https://192.168.200.50"
$api_username_oxidized = "admin"
$api_password_oxidized = "Greenet1!"

# prepare the rest client ssl stuff
def prepare_rest_client_oxidized(api_url_oxidized)
    options = { :user => $api_username_oxidized, :password => $api_password_oxidized, :verify_ssl => OpenSSL::SSL::VERIFY_NONE }
    res = RestClient::Resource.new(URI.encode(api_url_oxidized), options)
  return res
end

def get_oxidized()
  api_url_oxidized = $api_url_base_oxidized + "/oxidized/nodes/stats.json"
  rest_client = prepare_rest_client_oxidized(api_url_oxidized)
  headers = {"Content-Type" => "application/json", "Accept" => "application/json"}

  return rest_client.get(headers)
end

SCHEDULER.every '300s', allow_overlapping: false do

  oxidized_json = get_oxidized()
  oxidized_result = JSON.parse(oxidized_json.body)
 
  
  #create array for storing
	oxi_jsonarray=Array.new
	oxi_modelarray=Array.new
	oxi_statusarray=Array.new
 
 
#loop through the results and get number of success and failures

devices=0
success=0
fail=0
oxidized_result.each do |key1, key2|

devices += 1
	key2.each do | key1, key2, key3 |
		if key1 == "success"
		success += 1
		elsif key1 == "no_connection"
		fail += 1
		else
		
		end	
	end
end

  
oxidized_rows = [{"label"=> "Devices","value"=> devices} , {"label"=> "Successful","value"=> success } , {"label"=> "Failed Jobs","value"=> fail }] 

send_event('oxidized', {  items: oxidized_rows } ) 


 
 
end #Scheduler end
 
 
 
#Cacti poller status

SCHEDULER.every '60s',allow_overlapping: false do 

#Open the file
#The file should contain one line in this format(Taken from cacti.log) use bash to find and extract that single line.
#04/16/2016 12:17:02 AM - SYSTEM STATS: Time:0.9396 Method:spine Processes:1 Threads:20 Hosts:2 HostsPerProcess:2 DataSources:0 RRDsProcessed:0

file = File.open('/usr/share/dashinga2/cacti')
contents = file.read

#Split the file in to different fields
date, time, ampm, dash , system , stats, pollertime, method, proc, threads, hosts, hostspp, ds, rrds = contents.split(' ')

#remove from fields
pollertime 	= pollertime.gsub(/[^0-9,.]/, "")
pollertime 	= pollertime.to_f.round(2)
hosts		= hosts.gsub(/[^0-9,.]/, "")
ds 			= ds.gsub(/[^0-9,.]/, "")
rrds 		= rrds.gsub(/[^0-9,.]/, "")


cacti_rows = [{"label"=> "Last run","value"=> time} , {"label"=> "Run time","value"=> pollertime} , {"label"=> "Hosts","value"=> hosts }, {"label"=> "Datasources","value"=> ds }, {"label"=> "RRDs","value"=> rrds }] 

send_event('cacti', {  items: cacti_rows } ) 

end
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 




