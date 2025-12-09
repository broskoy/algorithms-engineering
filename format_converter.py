import osmium
import math

# --- Configuration ---
INPUT_FILE = "eindhoven.osm.pbf"
NODES_OUTPUT = "nodes.csv"
EDGES_OUTPUT = "edges.csv"

# Default speeds (km/h) by OSM highway type for travel-time weighting
DEFAULT_SPEED_KMH = {
    "motorway": 110,
    "motorway_link": 70,
    "trunk": 90,
    "trunk_link": 70,
    "primary": 70,
    "primary_link": 60,
    "secondary": 60,
    "secondary_link": 50,
    "tertiary": 50,
    "tertiary_link": 40,
    "unclassified": 40,
    "residential": 30,
    "living_street": 10,
    "service": 20,
    "cycleway": 20,
    "path": 10,
}
DEFAULT_FALLBACK_KMH = 50  # Used when no tag-based speed is available

def haversine(lon1, lat1, lon2, lat2):
    """Calculates distance in meters between two coordinates."""
    R = 6371000 
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2) * math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _parse_maxspeed(value):
    """Parse OSM maxspeed tag into meters/second, return None if unknown."""
    if not value:
        return None
    txt = value.strip().lower()
    if txt == "none":
        return None

    # mph handling
    if txt.endswith("mph"):
        num_txt = txt.replace("mph", "").strip()
        try:
            mph = float(num_txt)
            return mph * 0.44704  # mph -> m/s
        except ValueError:
            return None

    # km/h or bare number
    for token in ("km/h", "kph", "kmh"):
        txt = txt.replace(token, "")
    try:
        kmh = float(txt.strip())
        return kmh / 3.6  # km/h -> m/s
    except ValueError:
        return None


def estimate_speed_mps(tags):
    """Estimate speed (m/s) from maxspeed tag or highway type."""
    # 1) Explicit maxspeed if present
    maxspeed_raw = tags.get('maxspeed')
    speed = _parse_maxspeed(maxspeed_raw)
    if speed:
        return speed

    # 2) Highway-based defaults
    highway = tags.get('highway')
    if highway in DEFAULT_SPEED_KMH:
        return DEFAULT_SPEED_KMH[highway] / 3.6

    # 3) Fallback
    return DEFAULT_FALLBACK_KMH / 3.6

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
                
                # 2. Calculate Weight (travel time in seconds)
                dist = haversine(start_node.lon, start_node.lat, end_node.lon, end_node.lat)
                speed = estimate_speed_mps(w.tags)
                weight = dist / speed if speed else dist / (50/3.6)  # fallback to distance if speed missing
                
                # 3. Write Edge: "source,target,weight"
                self.e_writer.write(f"{u},{v},{weight:.2f}\n")
                
                # 4. Handle Bidirectional Roads
                if w.tags.get('oneway') != 'yes':
                    self.e_writer.write(f"{v},{u},{weight:.2f}\n")
                    
            except osmium.InvalidLocationError:
                # Sometimes PBF data is incomplete for a specific node
                continue

# --- Execution ---
print("Processing PBF...")
with open(NODES_OUTPUT, 'w') as nf, open(EDGES_OUTPUT, 'w') as ef:
    # Headers
    nf.write("id,lat,lon\n")
    ef.write("source,target,weight\n")  # weight = travel time (seconds)
    
    writer = GraphWriter(nf, ef)
    # locations=True is CRITICAL: it caches coords so w.nodes[i].lat works
    writer.apply_file(INPUT_FILE, locations=True)

print(f"Done. Mapped {writer.next_index} nodes. Ready for Zig.")
