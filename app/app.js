const http = require('http');

// Simulated fault: logs errors on a timer every 15 seconds
// Works even without external traffic hitting the app
setInterval(() => {
  console.error('ERROR: Simulated fault triggered!');
  console.error('Error: Unhandled exception in request handler - memory leak detected');
}, 15000);

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', timestamp: new Date().toISOString() }));
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Hello World from AWS DevOps!\n');
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
