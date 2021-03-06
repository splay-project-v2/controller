# Models a graph as derived from the topology_parser and exposes methods specialized for
# network graphs (kbps on links, shortest paths)
require 'algorithms' # for Fibonacci Heap, from https://github.com/kanwei/algorithms
include Containers

class Graph
  # Constructor
  def initialize
    @g = {} # the graph // {node => { edge1 => weight, edge2 => weight}, node2 => ...
    @nodes = []
    @INFINITY = 1 << 64
  end

  def add_edge(s, t, w) # s= source, t= target, w= weight
    # puts "Adding edge #{s} #{t}"
    if !@g.key?(s)
      @g[s] = { t => w }
    else
      @g[s][t] = w
    end
    # Begin code for non directed graph (inserts the other edge too)
    # if (not @g.has_key?(t))
    #  @g[t] = {s=>w}
    # else
    #  @g[t][s] = w
    # end
    # End code for non directed graph (ie. delete me if you want it directed)
    @nodes << s unless @nodes.include?(s)
    @nodes << t unless @nodes.include?(t)
  end

  # based of wikipedia's pseudocode: http://en.wikipedia.org/wiki/Dijkstra's_algorithm
  # uses the int_delayms field in the decorator of the node to compute paths.
  # The original implementation uses directly the weight of the field, an integer.
  # Use Fibonacci Heap to get current minimum.
  def dijkstra(s)
    @d = {}
    @prev = {}
    @nodes.each do |i|
      @d[i] = @INFINITY
      @prev[i] = -1
    end
    @d[s] = 0
    q = @nodes.compact
    heap = MinHeap.new # #fibonacci heap
    q.each do |n|
      heap.push(@d[n], n)
    end
    until q.empty?
      # u = nil
      # q.each do |min|
      #  if (not u) or (@d[min] and @d[min] < @d[u])
      #    u = min
      #  end
      # end

      u = heap.pop

      break if @d[u] == @INFINITY

      q -= [u]

      @g[u].keys.each do |v|
        alt = @d[u] + @g[u][v]['int_delayms']
        next unless alt < @d[v]

        @d[v] = alt
        # update the value associated with key
        heap.delete(v)
        heap.push(alt, v)

        @prev[v] = u
      end
    end
  end

  # To print the full shortest route to a node
  def print_path(dest)
    print_path @prev[dest] if @prev[dest] != -1
    print ">#{dest}"
  end

  # Gets all shortests paths using dijkstra

  def shortest_paths(s)
    @source = s
    dijkstra s
    puts "Source: #{@source}"
    @nodes.each do |dest|
      puts "\nTarget: #{dest}"
      print_path dest
      if @d[dest] != @INFINITY
        puts "\nDistance: #{@d[dest]}"
      else
        puts "\nNO PATH"
      end
    end
  end

  def shortest_paths_compact(s)
    @source = s
    dijkstra s
    @nodes.each do |dest|
      if @d[dest] != @INFINITY
        puts "#{@source} #{dest} #{@d[dest]}"
      else
        puts "\nNO PATH"
      end
    end
  end

  def link_latency(src, dest)
    if !@g.key?(src)
      -1
    else
      @g[src][dest]['int_delayms']
     end
  end

  # This is a valid path, simply check the delays on each link and sum
  def path_latency(path)
    tot_latency = 0
    path.length.times do |i|
      tot_latency += link_latency(path[i], path[i + 1]) if (i + 1) < path.length
    end
    tot_latency
  end

  def link_kbps(src, dest)
    if !@g.key?(src)
      -1
    else
      @g[src][dest]['dbl_kbps']
     end
  end

  def path_kbps(path)
    min_kbps = @INFINITY
    path.length.times do |i|
      next unless (i + 1) < path.length

      current_hop = link_kbps(path[i], path[i + 1])
      min_kbps = current_hop if current_hop < min_kbps
    end
    min_kbps
  end

  def path_hops_kbps(path)
    @hops = []
    path.length.times do |i|
      if (i + 1) < path.length
        current_hop = link_kbps(path[i], path[i + 1])
        @hops << current_hop
       end
    end
    @hops
  end

  # The result will be JSON-encoded and sent to every splayd to the job.
  def splay_topology(virtual_nodes)
    topology = {}
    virtual_nodes.each_key  do |node_x|
      topology[node_x] = {} # one entry per node
      dijkstra node_x # only once per vertex
      virtual_nodes.each_key do |node_y|
        next unless node_x != node_y

        topology[node_x][node_y] = []
        path_x_y = path(node_x, node_y)
        topology[node_x][node_y][0] = path_latency(path_x_y)
        topology[node_x][node_y][1] = path_kbps(path_x_y)
        topology[node_x][node_y][2] = path_x_y # raw path
        topology[node_x][node_y][3] = path_hops_kbps(path_x_y) # inter-hop bw,required for congestion/dyn adj
      end
    end
    topology
  end

  # #recursive call
  def path0(dest, p)
    if @prev[dest] != -1
      path0(@prev[dest], p)
      p << @prev[dest]
     end
  end

  # Assume that 'dijkstra src' has been already invoked
  def path(_src, dest)
    p = []
    path = path0(dest, p)
    p << dest
    p
  end
end
