import osmium
import math

# --- Configuration ---
INPUT_FILE = "eindhoven.osm.pbf"
NODES_OUTPUT = "nodes.csv"
EDGES_OUTPUT = "edges.csv"

def haversine(lon1, lat1, lon2, lat2):
    """Calculates distance in meters between two coordinates."""
    R = 6371000 
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2) * math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))

class GraphWriter(osmium.SimpleHandler):
    def __init__(self, n_writer, e_writer):
        super(GraphWriter, self).__init__()
        self.n_writer = n_writer
        self.e_writer = e_writer
        
        # Map OSM ID (huge int) -> Dense Index (0, 1, 2...)
        self.id_map = {}
        self.next_index = 0

    def get_or_create_node(self, osm_node_ref):
        """
        If we've seen this OSM node before, return its existing dense index.
        If not, assign a new index (0..N), write it to CSV, and store the mapping.
        """
        osm_id = osm_node_ref.ref
        
        if osm_id not in self.id_map:
            # New Node: assign next sequential index
            idx = self.next_index
            self.id_map[osm_id] = idx
            self.next_index += 1
            
            # Write to nodes.csv immediately: "index,lat,lon"
            self.n_writer.write(f"{idx},{osm_node_ref.lat:.7f},{osm_node_ref.lon:.7f}\n")
            
        return self.id_map[osm_id]

    def way(self, w):
        # Filter: Only routable roads
        if 'highway' not in w.tags: return
        
        # Iterate segments
        for i in range(len(w.nodes) - 1):
            start_node = w.nodes[i]
            end_node = w.nodes[i+1]

            try:
                # 1. Get/Create Dense IDs
                u = self.get_or_create_node(start_node)
                v = self.get_or_create_node(end_node)
                
                # 2. Calculate Weight
                dist = haversine(start_node.lon, start_node.lat, end_node.lon, end_node.lat)
                
                # 3. Write Edge: "source,target,weight"
                self.e_writer.write(f"{u},{v},{dist:.2f}\n")
                
                # 4. Handle Bidirectional Roads
                if w.tags.get('oneway') != 'yes':
                    self.e_writer.write(f"{v},{u},{dist:.2f}\n")
                    
            except osmium.InvalidLocationError:
                # Sometimes PBF data is incomplete for a specific node
                continue

# --- Execution ---
print("Processing PBF...")
with open(NODES_OUTPUT, 'w') as nf, open(EDGES_OUTPUT, 'w') as ef:
    # Headers
    nf.write("id,lat,lon\n")
    ef.write("source,target,weight\n")
    
    writer = GraphWriter(nf, ef)
    # locations=True is CRITICAL: it caches coords so w.nodes[i].lat works
    writer.apply_file(INPUT_FILE, locations=True)

print(f"Done. Mapped {writer.next_index} nodes. Ready for Zig.")
