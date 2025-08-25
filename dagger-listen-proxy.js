const http = require('http');

const DAGGER_PORT = 8090;
const PROXY_PORT = 9999;
const SESSION_TOKEN = 'mytestsession';

console.log(`Starting proxy on port ${PROXY_PORT}`);
console.log(`Forwarding to Dagger listen on port ${DAGGER_PORT}`);

const server = http.createServer((req, res) => {
  console.log(`\n[${new Date().toISOString()}] ${req.method} ${req.url}`);
  
  let body = '';
  req.on('data', chunk => body += chunk.toString());
  
  req.on('end', () => {
    console.log('Request body length:', body.length);
    
    // Try first without auth
    const makeRequest = (includeAuth) => {
      const headers = {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
        'Accept': 'application/json'
      };
      
      if (includeAuth) {
        headers['Authorization'] = 'Basic ' + Buffer.from(SESSION_TOKEN + ':').toString('base64');
        console.log('Retrying with auth...');
      }
      
      const options = {
        hostname: 'localhost',
        port: DAGGER_PORT,
        path: req.url,
        method: req.method,
        headers: headers
      };
      
      const proxyReq = http.request(options, (proxyRes) => {
        console.log('Dagger response status:', proxyRes.statusCode);
        
        let responseBody = '';
        
        proxyRes.on('data', chunk => {
          responseBody += chunk.toString();
        });
        
        proxyRes.on('end', () => {
          // If unauthorized, retry with auth
          if (proxyRes.statusCode === 401 && !includeAuth) {
            makeRequest(true);
            return;
          }
          
          console.log('Response length:', responseBody.length);
          if (responseBody.length < 1000) {
            console.log('Response:', responseBody);
          } else {
            console.log('Response preview:', responseBody.substring(0, 500) + '...');
          }
          
          res.statusCode = proxyRes.statusCode;
          Object.keys(proxyRes.headers).forEach(key => {
            res.setHeader(key, proxyRes.headers[key]);
          });
          
          res.end(responseBody);
        });
      });
      
      proxyReq.on('error', (e) => {
        console.error('Proxy error:', e.message);
        res.writeHead(500);
        res.end(JSON.stringify({ error: e.message }));
      });
      
      proxyReq.write(body);
      proxyReq.end();
    };
    
    makeRequest(false);
  });
});

server.listen(PROXY_PORT, () => {
  console.log(`✅ Proxy ready on http://localhost:${PROXY_PORT}`);
  console.log('Forwarding GraphQL requests to Dagger...');
});