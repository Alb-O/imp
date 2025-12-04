// Graph data injected by Nix
const gData = /*GRAPH_DATA*/;
const clusterColors = /*CLUSTER_COLORS*/;
const defaultColor = '#9e9e9e';

// Build neighbor/link references and track outgoing edges
const hasOutgoing = new Set();
gData.links.forEach(link => {
  const a = gData.nodes.find(n => n.id === link.source);
  const b = gData.nodes.find(n => n.id === link.target);
  if (a && b) {
    hasOutgoing.add(a.id);
    !a.neighbors && (a.neighbors = []);
    !b.neighbors && (b.neighbors = []);
    a.neighbors.push(b);
    b.neighbors.push(a);
    !a.links && (a.links = []);
    !b.links && (b.links = []);
    a.links.push(link);
    b.links.push(link);
  }
});

// Mark sink nodes (output configs with no outgoing edges)
gData.nodes.forEach(node => {
  const isOutputConfig = node.group === 'outputs.nixosConfigurations' || node.group === 'outputs.homeConfigurations';
  node.isSink = isOutputConfig && !hasOutgoing.has(node.id);
});

// Helper to get node radius
const getNodeRadius = node => node.isSink ? 20 : Math.sqrt(node.val + 2) * 4;
const hoverPadding = 8; // Extra hover area around nodes

// Build legend
const groups = [...new Set(gData.nodes.map(n => n.group))].sort();
const legend = document.getElementById('legend');
groups.forEach(g => {
  const item = document.createElement('div');
  item.className = 'legend-item';
  item.innerHTML = `<div class="legend-color" style="background:${clusterColors[g] || defaultColor}"></div><span>${g.replace('.', ' / ')}</span>`;
  legend.appendChild(item);
});

const highlightNodes = new Set();
const highlightLinks = new Set();
let hoverNode = null;

// Animated highlight state (0 = not highlighted, 1 = fully highlighted)
const nodeHighlight = new Map(); // node.id -> current value
const linkHighlight = new Map(); // link index -> current value
const transitionSpeed = 0.15; // How fast to animate (0-1 per frame)

// Interpolate highlights each frame
function updateHighlights() {
  gData.nodes.forEach(node => {
    const target = highlightNodes.has(node) ? 1 : 0;
    const current = nodeHighlight.get(node.id) || 0;
    const next = current + (target - current) * transitionSpeed;
    nodeHighlight.set(node.id, Math.abs(next - target) < 0.01 ? target : next);
  });
  gData.links.forEach((link, i) => {
    const target = highlightLinks.has(link) ? 1 : 0;
    const current = linkHighlight.get(i) || 0;
    const next = current + (target - current) * transitionSpeed;
    linkHighlight.set(i, Math.abs(next - target) < 0.01 ? target : next);
  });
}

// Color interpolation helper
function lerpColor(a, b, t) {
  const parse = c => c.match(/[\d.]+/g).map(Number);
  const [r1,g1,b1,a1=1] = parse(a);
  const [r2,g2,b2,a2=1] = parse(b);
  const r = Math.round(r1 + (r2-r1)*t);
  const g = Math.round(g1 + (g2-g1)*t);
  const bl = Math.round(b1 + (b2-b1)*t);
  const al = a1 + (a2-a1)*t;
  return `rgba(${r},${g},${bl},${al.toFixed(2)})`;
}

// Animated dash settings
const dashLen = 4;
const gapLen = 6;
const dashAnimateTime = 400;
const animateStart = +new Date();

const Graph = new ForceGraph(document.getElementById('graph'))
  .graphData(gData)
  .backgroundColor('#2d2d2d')
  .nodeId('id')
  .nodeLabel(node => node.isSink ? null : node.name.replace(/\n/g, '<br>'))
  .nodeVal(node => node.isSink ? 12 : node.val + 2)
  .nodeCanvasObjectMode(() => 'replace')
  .nodeCanvasObject((node, ctx, globalScale) => {
    const radius = getNodeRadius(node);
    const color = clusterColors[node.group] || defaultColor;
    const hl = nodeHighlight.get(node.id) || 0;

    // Draw highlight ring with animated opacity/size
    if (hl > 0.01) {
      ctx.beginPath();
      ctx.arc(node.x, node.y, radius * (1 + 0.4 * hl), 0, 2 * Math.PI);
      const hlColor = node === hoverNode ? `rgba(255,87,34,${hl})` : `rgba(255,171,0,${hl})`;
      ctx.fillStyle = hlColor;
      ctx.fill();
    }

    // Draw node
    ctx.beginPath();
    ctx.arc(node.x, node.y, radius, 0, 2 * Math.PI);
    ctx.fillStyle = color;
    ctx.fill();

    // Draw text label for sink nodes
    if (node.isSink) {
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 10px sans-serif';
      ctx.fillText(node.name.split('\n')[0], node.x, node.y);
    }
  })
  .nodePointerAreaPaint((node, color, ctx) => {
    const radius = getNodeRadius(node) + hoverPadding;
    ctx.beginPath();
    ctx.arc(node.x, node.y, radius, 0, 2 * Math.PI);
    ctx.fillStyle = color;
    ctx.fill();
  })
  .linkSource('source')
  .linkTarget('target')
  .linkWidth(link => {
    const hl = linkHighlight.get(gData.links.indexOf(link)) || 0;
    return 2 + hl * 1.5;
  })
  .linkColor(link => {
    const hl = linkHighlight.get(gData.links.indexOf(link)) || 0;
    return lerpColor('rgba(255,255,255,0.4)', 'rgba(255,87,34,1)', hl);
  })
  .linkLineDash([dashLen, gapLen])
  .linkDirectionalArrowLength(6)
  .linkDirectionalArrowRelPos(1)
  .linkDirectionalArrowColor(link => {
    const hl = linkHighlight.get(gData.links.indexOf(link)) || 0;
    return lerpColor('rgba(255,255,255,0.6)', 'rgba(255,87,34,1)', hl);
  })
  .onNodeHover(node => {
    highlightNodes.clear();
    highlightLinks.clear();

    if (node) {
      highlightNodes.add(node);
      (node.neighbors || []).forEach(n => highlightNodes.add(n));
      (node.links || []).forEach(l => highlightLinks.add(l));
    }

    hoverNode = node || null;

    // Update info panel
    const info = document.getElementById('info');
    if (node) {
      info.innerHTML = `
        <h3>${node.name.replace(/\n/g, ', ')}</h3>
        <div class="cluster">${node.group.replace('.', ' / ')}</div>
        <div class="nodes">${node.name}</div>
      `;
    } else {
      info.innerHTML = '<h3>imp Registry</h3><div class="hint">Hover over nodes to highlight connections</div>';
    }
  })
  .onLinkHover(link => {
    highlightNodes.clear();
    highlightLinks.clear();

    if (link) {
      highlightLinks.add(link);
      highlightNodes.add(link.source);
      highlightNodes.add(link.target);
    }
  })
  .onNodeDragEnd(node => {
    // Fix node position after drag
    node.fx = node.x;
    node.fy = node.y;
  });

// Animation loop for dashed lines and smooth highlights
(function animate() {
  updateHighlights();

  const t = ((+new Date() - animateStart) % dashAnimateTime) / dashAnimateTime;
  const lineDash = t < 0.5
    ? [0, gapLen * t * 2, dashLen, gapLen * (1 - t * 2)]
    : [dashLen * (t - 0.5) * 2, gapLen, dashLen * (1 - (t - 0.5) * 2), 0];
  Graph.linkLineDash(lineDash);

  requestAnimationFrame(animate);
})();
