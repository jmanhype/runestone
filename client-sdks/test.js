const RunestoneClient = require('./index.js');

async function test() {
  const client = new RunestoneClient('sk-test-key');
  
  try {
    // Test chat completion
    const chatResponse = await client.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: 'Hello!' }]
    });
    console.log('Chat Response:', chatResponse);
    
    // Test models list
    const models = await client.models.list();
    console.log('Models:', models);
    
    // Test embeddings
    const embeddings = await client.embeddings.create({
      model: 'text-embedding-ada-002',
      input: 'Hello world'
    });
    console.log('Embeddings:', embeddings);
    
  } catch (error) {
    console.error('Error:', error.message);
  }
}

test();
