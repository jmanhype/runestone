const http = require('http');

const DAGGER_PORT = parseInt(process.env.DAGGER_PORT || '49382');
const DAGGER_TOKEN = process.env.DAGGER_TOKEN || 'a885901a-5121-4041-a9b5-d62c0516feb9';
const PROXY_PORT = 9999;

console.log(`Starting proxy on port ${PROXY_PORT}`);
console.log(`Forwarding to Dagger on port ${DAGGER_PORT}`);
console.log(`Using token: ${DAGGER_TOKEN.substring(0, 8)}...`);

const server = http.createServer((req, res) => {
  console.log(`\nIncoming request: ${req.method} ${req.url}`);
  
  let body = '';
  req.on('data', chunk => body += chunk.toString());
  
  req.on('end', () => {
    console.log('Request body:', body.substring(0, 200) + (body.length > 200 ? '...' : ''));
    
    const authHeader = 'Basic ' + Buffer.from(DAGGER_TOKEN + ':').toString('base64');
    
    const options = {
      hostname: 'localhost',
      port: DAGGER_PORT,
      path: req.url,
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
        'Authorization': authHeader,
        'Accept': 'application/json'
      }
    };
    
    console.log('Forwarding with auth:', authHeader.substring(0, 20) + '...');
    
    const proxyReq = http.request(options, (proxyRes) => {
      console.log('Dagger response status:', proxyRes.statusCode);
      console.log('Dagger response headers:', JSON.stringify(proxyRes.headers));
      
      let responseBody = '';
      
      proxyRes.on('data', chunk => {
        responseBody += chunk.toString();
      });
      
      proxyRes.on('end', () => {
        console.log('Response body length:', responseBody.length);
        console.log('Response preview:', responseBody.substring(0, 500));
        
        // Set response headers
        res.statusCode = proxyRes.statusCode;
        Object.keys(proxyRes.headers).forEach(key => {
          res.setHeader(key, proxyRes.headers[key]);
        });
        
        res.end(responseBody);
      });
    });
    
    proxyReq.on('error', (e) => {
      console.error('Proxy error:', e);
      res.writeHead(500);
      res.end(JSON.stringify({ error: e.message }));
    });
    
    proxyReq.write(body);
    proxyReq.end();
  });
});

server.listen(PROXY_PORT, () => {
  console.log(`✅ Proxy ready on http://localhost:${PROXY_PORT}`);
});