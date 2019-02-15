## Parser for ModelNet Topology Descriptor
## <topology>
##   <vertices>
##     <vertex int_idx="1" role="gateway" />
##     <vertex int_idx="2" role="virtnode" int_vn="0" />
##     </vertices>
##   <edges>
##     <edge int_dst="1" int_src="2" int_idx="0" int_len="300" specs="client-stub" int_delayms="1" />
##     <edge int_dst="2" int_src="1" int_idx="1" int_len="300" specs="client-stub" dbl_kbps="768" />
##     <edge int_dst="1" int_src="5" int_idx="0" int_len="20" specs="stub-stub" />
##   </edges>
##   <specs>
##     <client-stub dbl_plr="0" dbl_kbps="64" int_delayms="100" int_qlen="10" />
##     <stub-stub dbl_plr="0" dbl_kbps="1000" int_delayms="20" int_qlen="10" />
##   </specs>
## </topology>

require 'nokogiri' # #to quickly read XML. gems install nokogiri
# require 'dijkstra'
require File.expand_path(File.join(File.dirname(__FILE__), 'dijkstra'))

class TopologyParser
  def initialize
    # the default values, as stored in the XML file in the specs block
    @defaults = {}
    @virtual_nodes = {}
    @middle_nodes = {}
    @gr = Graph.new
  end

  attr_reader :defaults

  def virtualnodes
    @virtual_nodes
  end

  def middlenodes
    @middle_nodes
  end

  # #return the built graph
  def parse(input, from_file = true)
    # print(input)
    if from_file
      xml = File.open(input, 'r')
      graph = Nokogiri::XML(xml)
      xml.close
    else
      # puts("Current Ruby  version: "+RUBY_VERSION)
      # puts("Parsing topology file [raw]:"+input)
      # puts("Parsing topology file [class]:"+input.class.to_s)
      # puts("Parsing topology file:"+input[2..(input.length-3)].chomp)

      if RUBY_VERSION == '1.9.2'
        input.delete! "\n", "\t", '\\'
        graph = Nokogiri::XML((input[2..(input.length - 3)]))
      else
        graph = Nokogiri::XML(input)
      end
    end

    ## full traversal here
    ## check if it's more efficient with XPath query
    graph.root.traverse do |elem|
      if elem.name == 'specs'
        elem.traverse do |s|
          # <client-stub dbl_plr="0" dbl_kbps="64" int_delayms="100" int_qlen="10" />
          # <stub-stub dbl_plr="0" dbl_kbps="1000" int_delayms="20" int_qlen="10" />
          if (s.name == 'client-stub') || s.name == 'stub-stub' || (s.name == 'transit-transit') || (s.name = 'stub-transit') || (s.name = 'client-client')
            @defaults[s.name] = {}
            @defaults[s.name]['dbl_plr'] = s['dbl_plr'].to_i if s['dbl_plr']
            @defaults[s.name]['dbl_kbps'] = s['dbl_kbps'].to_i if s['dbl_kbps']
            if s['int_delayms'] then @defaults[s.name]['int_delayms'] = s['int_delayms'].to_i end
            @defaults[s.name]['int_qlen'] = s['int_qlen'].to_i if s['int_qlen']
          end
        end
      end
    end

    # The topology is expected to have directed edges, but the XML can be incomplete.
    # A completion step is added at the end of the parsing to add the missing edges.
    added_edges = {}

    graph.root.traverse do |elem|
      # <edge int_dst="1" int_src="2" int_idx="0" int_len="300" specs="client-stub" int_delayms="1" dbl_kbps="768"  />
      if elem.name == 'edge'
        edge_attribs = {} # will store fields used by dijkstra, decorates edges
        src = nil
        dst = nil
        elem.traverse do |e|
          src = e['int_src']
          dst = e['int_dst']
          # puts e['int_dst']+" -> "+e['int_src']+" "+e['int_len']
          edge_spec = e['specs']

          # #use defaults, then overwrite if value is given
          edge_attribs['int_delayms'] = @defaults[edge_spec]['int_delayms']
          unless e['int_delayms'].nil?
            edge_attribs['int_delayms'] = e['int_delayms'].to_i
          end
          #  edge_attribs['int_delayms'] = @defaults[edge_spec]['int_delayms']
          # end
          edge_attribs['dbl_kbps'] = @defaults[edge_spec]['dbl_kbps']
          edge_attribs['dbl_kbps'] = e['dbl_kbps'].to_i unless e['dbl_kbps'].nil?
        end

        @gr.add_edge(src, dst, edge_attribs)
        added_edges[[src, dst]] = edge_attribs

        # <vertex int_idx="2" role="virtnode" int_vn="1" />
      elsif elem.name == 'vertex'
        elem.traverse do |e|
          role = e['role']
          if role == 'virtnode'
            @virtual_nodes[e['int_vn']] = e['int_idx']
          else
            @middle_nodes[e['int_idx']] = e['int_idx'] # #Gateway nodes do not ship int_vn number, using int_idx
          end
        end
      end
    end
    $log.info('Topology parsing complete.') if $log
    # complete the graph with the missing edges if any
    added_edges.each do |key, _value|
      # key.each{|a| puts a}
      # puts key[0],key[1],value.to_s

      if added_edges[[key[1], key[0]]].nil?
        # add missing edge using same attribs as existing one (should use defaults instead)
        @gr.add_edge(key[1], key[0], added_edges[[key[0], key[1]]])
      end
    end
    $log.info('Topology completion complete.') if $log
    @gr
  end
end
