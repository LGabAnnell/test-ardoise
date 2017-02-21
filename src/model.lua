return function (Layer, example, ref)

  local defaults = Layer.key.defaults
  local meta     = Layer.key.meta
  local refines  = Layer.key.refines

  local record     = Layer.new { name = "data.record" }
  local collection = Layer.new { name = "data.collection" }

  collection [meta] = {
    [collection] = {
      key_type        = false,
      value_type      = false,
      key_container   = false,
      value_container = false,
      minimum         = false,
      maximum         = false,
    },
  }
  collection [defaults] = {
    Layer.reference (collection) [meta] [collection].value_type,
  }

  local gui = Layer.new { name = "gui" }

  local position = Layer.new { name = "position" }

  local graph = Layer.new { name = "graph" }

  graph [refines] = {
    record,
  }

  graph [meta] = {}

  -- Vertices are empty in base graph.
  graph [meta].vertex_type = {
    [refines] = {
      record,
    },
    [meta] = {},
  }

  -- Arrows are records with only one predefined field: `vertex`.
  -- It points to the destination of the arrow, that must be a vertex of the
  -- graph.
  -- Edges have no label in base graph.
  -- They only contain zero to several arrows. The arrow type is defined for
  -- each edge type.
  -- The `default` key states that all elements within the `arrows` container
  -- are of type `arrow_type`.
  graph [meta].edge_type = {
    [refines] = {
      record,
    },
    [meta] = {
      arrow_type = {
        [refines] = {
          record,
        },
        [meta] = {
          [record] = {
            vertex = {
              value_type      = Layer.reference (graph) [meta].vertex_type,
              value_container = Layer.reference (graph).vertices,
            }
          }
        },
        vertex = nil,
      },
    },
  }

  graph [meta].edge_type.arrows = {
    [refines] = {
      collection,
    },
    [meta] = {
      [collection] = {
        value_type = Layer.reference (graph [meta].edge_type) [meta].arrow_type,
      }
    },
  }

  -- A graph contains a collection of vertices.
  -- The `default` key states that all elements within the `vertices` container
  -- are of type `vertex_type`.
  graph.vertices = {
    [refines] = {
      collection,
    },
    [meta] = {
      [collection] = {
        value_type = Layer.reference (graph) [meta].vertex_type,
      },
    },
  }

  -- A graph contains a collection of edges.
  -- The `default` key states that all elements within the `edges` container
  -- are of type `edge_type`.
  graph.edges = {
    [refines] = {
      collection,
    },
    [meta] = {
      [collection] = {
        value_type = Layer.reference (graph) [meta].edge_type,
      },
    },
  }

  graph [meta].vertex_type [meta] [position] = {
    x = 0,
    y = 0,
  }

  graph [meta] [gui] = {}

  graph [meta] [gui].render = function (parameters)
    assert (type (parameters) == "table")
    local Adapter  = require "ardoises.js"
    local Copas    = require "copas"
    local Et       = require "etlua"
    local name     = assert (parameters.name  )
    local editor   = assert (parameters.editor)
    local layer    = assert (parameters.what  ).layer
    local target   = assert (parameters.target)
    local D3       = Adapter.window.d3
    local width    = assert (parameters.width )
    local height   = assert (parameters.height)
    local hidden   = {}
    local vertices = Adapter.js.new (Adapter.window.Array)
    local edges    = Adapter.js.new (Adapter.window.Array)
    for key, vertex in pairs (layer.vertices) do
      local data = Adapter.tojs {
        id = vertices.length,
        x  = vertex [position]
         and vertex [position].x
          or 0,
        y  = vertex [position]
         and vertex [position].y
          or 0,
        fx = vertex [position]
         and vertex [position].x,
        fy = vertex [position]
         and vertex [position].y,
      }
      hidden [data] = {
        id    = vertices.length,
        key   = key,
        proxy = vertex,
      }
      vertices [vertices.length] = data
    end
    for key, edge in pairs (layer.edges) do
      local data = Adapter.tojs {
        id = vertices.length,
        x  = 0,
        y  = 0,
      }
      hidden [data] = {
        id    = vertices.length,
        key   = key,
        proxy = edge,
      }
      vertices [vertices.length] = data
      for k, arrow in pairs (edge.arrows) do
        for i = 0, vertices.length-1 do
          local node = vertices [i]
          if arrow.vertex <= hidden [node].proxy then
            local link = Adapter.js.new (Adapter.window.Object)
            link.source = data
            link.target = node
            hidden [link] = {
              id    = edges.length,
              key   = k,
              proxy = arrow,
            }
            edges [edges.length] = link
          end
        end
      end
    end
    target.innerHTML = Et.render ([[
      <svg width="<%- width %>" height="<%- height %>" id="layer">
      </svg>
    ]], {
      width  = width,
      height = height,
    })
    local svg = D3:select "#layer"
    local g   = svg
      :append "g"
      :attr   ("class", ".ardoises-gui")
    local simulation = D3
      :forceSimulation ()
      :force ("link"  , D3:forceLink ():id (function (_, d) return d.id end))
      :force ("charge", D3:forceManyBody ())
      :force ("center", D3:forceCenter (width / 2, height / 2))
    local drag_start = function (_, vertex)
      simulation:alphaTarget (1):restart ()
      vertex.fx = vertex.x
      vertex.fy = vertex.y
    end
    local drag_drag = function (_, vertex)
      vertex.fx = D3.event.x
      vertex.fy = D3.event.y
    end
    local drag_stop = function (_, vertex)
      local Json = require "cjson"
      print (Json.encode {
        [name] = Et.render ([[
          layer.vertices [<%- key %>] [position] = {
            x = <%- x %>,
            y = <%- y %>,
          }
        ]], {
          key = type (hidden [vertex].key) == "string"
            and string.format ("%q", hidden [vertex].key)
             or hidden [vertex].key,
          x   = D3.event.x,
          y   = D3.event.y,
        })
      })
      Copas.addthread (function ()
        print (editor:patch {
          [name] = Et.render ([[
            layer.vertices [<%- key %>] [position] = {
              x = <%- x %>,
              y = <%- y %>,
            }
          ]], {
            key = type (hidden [vertex].key) == "string"
              and string.format ("%q", hidden [vertex].key)
               or hidden [vertex].key,
            x   = D3.event.x,
            y   = D3.event.y,
          })
        })
      end)
      vertex.fx = D3.event.x
      vertex.fy = D3.event.y
    end
    local links = g
      :selectAll ".ardoises-gui"
      :data      (edges)
      :enter     ()
      :append    "line"
      :attr      ("stroke", "white")
      :attr      ("stroke-width", 2)
    local nodes = g
      :selectAll ".ardoises-gui"
      :data   (vertices)
      :enter  ()
      :append (function (_, data)
         local proxy = hidden [data].proxy
         return proxy [meta] [gui].create {
           proxy = hidden [data],
           data  = data,
         }
       end)
      :call (D3:drag ():on ("start", drag_start):on ("drag", drag_drag):on ("end", drag_stop))
    local source_x = function (_, d) return d.source.x end
    local source_y = function (_, d) return d.source.y end
    local target_x = function (_, d) return d.target.x end
    local target_y = function (_, d) return d.target.y end
    local tick     = function ()
      links:attr ("x1", source_x)
           :attr ("y1", source_y)
           :attr ("x2", target_x)
           :attr ("y2", target_y)
      nodes:each (function (element, data)
        local proxy = hidden [data].proxy
        return proxy [meta] [gui].update {
          element = element,
          proxy   = hidden [data],
          data    = data,
        }
      end)
    end
    simulation:nodes (vertices):on ("tick", tick)
    simulation:force "link":links (edges)
    svg:call (D3:zoom ():on ("zoom", function ()
      g:attr ("transform", D3.event.transform)
    end))
    coroutine.yield ()
    simulation:stop ()
    vertices.length  = 0
    edges   .length  = 0
    target.innerHTML = [[]]
  end

  graph [meta].vertex_type [meta] [gui] = {}

  graph [meta].vertex_type [meta] [gui].create = function (parameters)
    local Adapter   = require "ardoises.js"
    local group     = Adapter.document:createElementNS (Adapter.window.d3.namespaces.svg, "g")
    local selection = Adapter.window.d3:select (group)
    selection
      :append "circle"
      :attr ("r", 50)
      :attr ("stroke", "white")
      :attr ("stroke-width", 3)
    return selection:node ()
  end

  graph [meta].vertex_type [meta] [gui].update = function (parameters)
    local Adapter = require "ardoises.js"
    Adapter.window.d3
      :select (parameters.element)
      :selectAll "circle"
      :attr ("cx", parameters.data.x)
      :attr ("cy", parameters.data.y)
  end

  graph [meta].edge_type [meta] [gui] = {}

  graph [meta].edge_type [meta] [gui].create = function (parameters)
    local Adapter   = require "ardoises.js"
    local group     = Adapter.document:createElementNS (Adapter.window.d3.namespaces.svg, "g")
    local selection = Adapter.window.d3:select (group)
    selection
      :append "circle"
      :attr ("r", 1)
      :attr ("stroke", "white")
    return selection:node ()
  end

  graph [meta].edge_type [meta] [gui].update = function (parameters)
    local Adapter = require "ardoises.js"
    Adapter.window.d3
      :select (parameters.element)
      :selectAll "circle"
      :attr ("cx", parameters.data.x)
      :attr ("cy", parameters.data.y)
  end

  local binary_edges = Layer.new { name = "graph.binary_edges" }

  binary_edges [refines] = {
    graph
  }

  binary_edges [meta].edge_type.arrows [meta] = {
    [collection] = {
      minimum = 2,
      maximum = 2,
    },
  }

  local directed = Layer.new { name = "graph.directed" }

  directed [refines] = {
    graph,
    binary_edges,
  }

  directed [meta].edge_type [meta] [record] = {
    source = {
      value_container = Layer.reference (directed).vertices,
    },
    target = {
      value_container = Layer.reference (directed).vertices,
    },
  }

  directed [meta].edge_type.arrows = {
    source = {
      vertex = Layer.reference (directed [meta].edge_type).source,
    },
    target = {
      vertex = Layer.reference (directed [meta].edge_type).target,
    },
  }

  local petrinet = Layer.new { name = "petrinet" }

  petrinet [refines] = {
    directed,
  }

  petrinet [meta].place_type = {
    [refines] = {
      Layer.reference (petrinet) [meta].vertex_type,
    },
    [meta] = {
      [record] = {
        identifier = false,
        marking    = false,
      }
    }
  }

  petrinet [meta].transition_type = {
    [refines] = {
      Layer.reference (petrinet) [meta].vertex_type,
    }
  }

  petrinet [meta].arc_type = {
    [refines] = {
      Layer.reference (petrinet) [meta].edge_type,
    },
  }

  petrinet.places = {
    [refines] = {
      collection,
    },
    [meta] = {
      [collection] = {
        value_type = Layer.reference (petrinet) [meta].place_type,
      }
    },
  }

  petrinet.transitions = {
    [refines] = {
      collection,
    },
    [meta] = {
      [collection] = {
        value_type = Layer.reference (petrinet) [meta].transition_type,
      }
    },
  }

  petrinet [meta].pre_arc_type = {
    [refines] = {
      Layer.reference (petrinet) [meta].arc_type,
    },
    [meta] = {
      [record] = {
        source = {
          value_container = Layer.reference (petrinet).places,
        },
        target = {
          value_container = Layer.reference (petrinet).transitions,
        },
      },
    },
  }

  petrinet [meta].post_arc_type = {
    [refines] = {
      Layer.reference (petrinet) [meta].arc_type,
    },
    [meta] = {
      [record] = {
        source = {
          value_container = Layer.reference (petrinet).transitions,
        },
        target = {
          value_container = Layer.reference (petrinet).places,
        },
      },
    },
  }

  petrinet.pre_arcs = {
    [refines] = {
      collection,
    },
    [meta] = {
      [collection] = {
        value_type = Layer.reference (petrinet) [meta].pre_arc_type,
      }
    },
  }

  petrinet.post_arcs = {
    [refines] = {
      collection,
    },
    [meta] = {
      [collection] = {
        value_type = Layer.reference (petrinet) [meta].post_arc_type,
      }
    },
  }

  petrinet.arcs = {
    [refines] = {
      Layer.reference (petrinet).pre_arcs,
      Layer.reference (petrinet).post_arcs,
    },
  }

  petrinet.vertices [refines] = {
    Layer.reference (petrinet).places,
    Layer.reference (petrinet).transitions,
  }
  petrinet.edges    [refines] = {
    Layer.reference (petrinet).arcs,
  }

  example [refines] = {
    petrinet,
  }
  example.places     .a  = {}
  example.transitions.b  = {}
  example.pre_arcs   .ab = {
    source = ref.places.a,
    target = ref.transitions.b,
  }

  -- Iteration over Petri net arcs:
  for id, arc in Layer.pairs (example.arcs) do
    print (id, arc.source, arc.target)
  end

  -- Iteration over graph edges:
  for id, edge in Layer.pairs (example.edges) do
    print (id, edge.source, edge.target)
  end

  -- Iteration over graph vertices:
  for id, vertex in Layer.pairs (example.vertices) do
    print (id, vertex)
  end

end
