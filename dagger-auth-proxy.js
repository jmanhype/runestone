const http = require('http');
const https = require('https');

const DAGGER_PORT = 8090;
const PROXY_PORT = 9999;

// Create proxy server
const server = http.createServer((req, res) => {
  let body = '';
  
  req.on('data', chunk => {
    body += chunk.toString();
  });
  
  req.on('end', () => {
    console.log('Incoming request:', req.method, req.url);
    console.log('Headers:', JSON.stringify(req.headers, null, 2));
    console.log('Body:', body);
    
    // Forward to Dagger with NO auth (since it's local)
    const options = {
      hostname: 'localhost',
      port: DAGGER_PORT,
      path: req.url,
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };
    
    const proxyReq = http.request(options, (proxyRes) => {
      let responseBody = '';
      
      proxyRes.on('data', (chunk) => {
        responseBody += chunk.toString();
      });
      
      proxyRes.on('end', () => {
        console.log('Dagger response status:', proxyRes.statusCode);
        console.log('Dagger response:', responseBody);
        
        // If we get an auth error, retry with auth header
        if (responseBody.includes('unauthorized') || responseBody.includes('401') || responseBody === '') {
          console.log('Retrying with auth...');
          
          const authOptions = {
            ...options,
            headers: {
              ...options.headers,
              'Authorization': 'Basic ' + Buffer.from('b862f688-dd56-4da6-8d78-48c38d78fbda:').toString('base64')
            }
          };
          
          const authReq = http.request(authOptions, (authRes) => {
            let authBody = '';
            authRes.on('data', chunk => authBody += chunk);
            authRes.on('end', () => {
              console.log('Auth retry response:', authBody);
              res.writeHead(authRes.statusCode, authRes.headers);
              res.end(authBody);
            });
          });
          
          authReq.write(body);
          authReq.end();
        } else {
          res.writeHead(proxyRes.statusCode, proxyRes.headers);
          res.end(responseBody);
        }
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
  console.log(`Dagger auth proxy running on port ${PROXY_PORT}`);
  console.log(`Forwarding to Dagger on port ${DAGGER_PORT}`);
});