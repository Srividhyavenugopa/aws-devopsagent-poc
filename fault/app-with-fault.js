const http = require('http');

const server = http.createServer((req, res) => {
  // Simulated fault: crashes 50% of requests
  if (Math.random() < 0.5) {
    console.error('ERROR: Simulated fault triggered!');
    throw new Error('Simulated fault - use DevOps Agent to find and fix this!');
  }

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
