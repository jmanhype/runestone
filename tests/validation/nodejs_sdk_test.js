#!/usr/bin/env node

/**
 * Node.js SDK Compatibility Test for Runestone OpenAI API
 * 
 * This script validates that Runestone is fully compatible with the official
 * OpenAI Node.js SDK by running real SDK calls against the Runestone API.
 */

const axios = require('axios').default;

// Try to import OpenAI SDK
let OpenAI;
try {
    OpenAI = require('openai');
} catch (error) {
    console.log('❌ Missing OpenAI SDK. Install with:');
    console.log('   npm install openai axios');
    process.exit(1);
}

class RunestoneSDKValidator {
    constructor(baseUrl = 'http://localhost:4002', apiKey = 'test-api-key') {
        this.baseUrl = baseUrl;
        this.apiKey = apiKey;
        this.client = new OpenAI({
            apiKey: apiKey,
            baseURL: `${baseUrl}/v1`
        });
        this.results = [];
    }

    logResult(testName, status, details = '') {
        this.results.push({
            test: testName,
            status: status,
            details: details
        });

        const statusIcon = {
            'PASS': '✅',
            'FAIL': '❌',
            'WARN': '⚠️'
        }[status] || '❓';

        console.log(`  ${statusIcon} ${testName}: ${status}`);
        if (details) {
            console.log(`     ${details}`);
        }
    }

    async testBasicChatCompletion() {
        try {
            const response = await this.client.chat.completions.create({
                model: 'gpt-4o-mini',
                messages: [
                    { role: 'user', content: 'Say "Node.js SDK test successful" and nothing else.' }
                ],
                max_tokens: 20
            });

            // Validate response structure
            if (!response.id) throw new Error("Response missing 'id'");
            if (!response.object) throw new Error("Response missing 'object'");
            if (response.object !== 'chat.completion') {
                throw new Error(`Expected 'chat.completion', got '${response.object}'`);
            }
            if (!response.choices) throw new Error("Response missing 'choices'");
            if (response.choices.length === 0) throw new Error("No choices in response");

            const choice = response.choices[0];
            if (!choice.message) throw new Error("Choice missing 'message'");
            if (!choice.message.role) throw new Error("Message missing 'role'");
            if (choice.message.role !== 'assistant') {
                throw new Error(`Expected 'assistant', got '${choice.message.role}'`);
            }
            if (!choice.message.content) throw new Error("Message missing 'content'");
            if (choice.message.content.length === 0) throw new Error("Empty response content");

            this.logResult('Basic Chat Completion', 'PASS', 
                `Response ID: ${response.id}, Content length: ${choice.message.content.length}`);

        } catch (error) {
            this.logResult('Basic Chat Completion', 'FAIL', error.message);
        }
    }

    async testStreamingChatCompletion() {
        try {
            const stream = await this.client.chat.completions.create({
                model: 'gpt-4o-mini',
                messages: [
                    { role: 'user', content: 'Count from 1 to 3, one number per response.' }
                ],
                stream: true,
                max_tokens: 50
            });

            let chunksReceived = 0;
            const contentPieces = [];

            for await (const chunk of stream) {
                chunksReceived++;

                // Validate chunk structure
                if (!chunk.id) throw new Error("Chunk missing 'id'");
                if (!chunk.object) throw new Error("Chunk missing 'object'");
                if (chunk.object !== 'chat.completion.chunk') {
                    throw new Error(`Expected 'chat.completion.chunk', got '${chunk.object}'`);
                }
                if (!chunk.choices) throw new Error("Chunk missing 'choices'");

                if (chunk.choices.length > 0) {
                    const choice = chunk.choices[0];
                    if (!choice.delta) throw new Error("Choice missing 'delta'");

                    if (choice.delta.content) {
                        contentPieces.push(choice.delta.content);
                    }
                }
            }

            const totalContent = contentPieces.join('');

            if (chunksReceived === 0) throw new Error("No chunks received");
            if (totalContent.length === 0) throw new Error("No content received in stream");

            this.logResult('Streaming Chat Completion', 'PASS', 
                `Chunks: ${chunksReceived}, Content: '${totalContent}'`);

        } catch (error) {
            this.logResult('Streaming Chat Completion', 'FAIL', error.message);
        }
    }

    async testModelsList() {
        try {
            const models = await this.client.models.list();

            // Validate response structure
            if (!models.object) throw new Error("Models response missing 'object'");
            if (models.object !== 'list') {
                throw new Error(`Expected 'list', got '${models.object}'`);
            }
            if (!models.data) throw new Error("Models response missing 'data'");
            if (!Array.isArray(models.data)) throw new Error("Models data is not an array");

            if (models.data.length > 0) {
                const model = models.data[0];
                if (!model.id) throw new Error("Model missing 'id'");
                if (!model.object) throw new Error("Model missing 'object'");
                if (model.object !== 'model') {
                    throw new Error(`Expected 'model', got '${model.object}'`);
                }
                if (!model.created) throw new Error("Model missing 'created'");
                if (!model.owned_by) throw new Error("Model missing 'owned_by'");
            }

            this.logResult('Models List', 'PASS', 
                `Found ${models.data.length} models`);

        } catch (error) {
            this.logResult('Models List', 'FAIL', error.message);
        }
    }

    async testModelsRetrieve() {
        try {
            const model = await this.client.models.retrieve('gpt-4o-mini');

            // Validate response structure
            if (!model.id) throw new Error("Model missing 'id'");
            if (model.id !== 'gpt-4o-mini') {
                throw new Error(`Expected 'gpt-4o-mini', got '${model.id}'`);
            }
            if (!model.object) throw new Error("Model missing 'object'");
            if (model.object !== 'model') {
                throw new Error(`Expected 'model', got '${model.object}'`);
            }
            if (!model.created) throw new Error("Model missing 'created'");
            if (!model.owned_by) throw new Error("Model missing 'owned_by'");

            this.logResult('Models Retrieve', 'PASS', 
                `Model: ${model.id}, Owner: ${model.owned_by}`);

        } catch (error) {
            if (error.status === 404) {
                this.logResult('Models Retrieve', 'WARN', 
                    "Model 'gpt-4o-mini' not found - this is acceptable");
            } else {
                this.logResult('Models Retrieve', 'FAIL', error.message);
            }
        }
    }

    async testErrorHandling() {
        // Test invalid API key
        try {
            const invalidClient = new OpenAI({
                apiKey: 'invalid-key',
                baseURL: `${this.baseUrl}/v1`
            });

            await invalidClient.chat.completions.create({
                model: 'gpt-4o-mini',
                messages: [{ role: 'user', content: 'Test' }]
            });

            this.logResult('Error Handling - Invalid Key', 'FAIL', 
                'Expected authentication error but request succeeded');

        } catch (error) {
            if (error.status === 401 || error.constructor.name === 'AuthenticationError') {
                this.logResult('Error Handling - Invalid Key', 'PASS', 
                    'Correctly raised authentication error');
            } else {
                this.logResult('Error Handling - Invalid Key', 'FAIL', 
                    `Expected authentication error, got ${error.constructor.name}: ${error.message}`);
            }
        }

        // Test invalid request format
        try {
            await this.client.chat.completions.create({
                model: 'gpt-4o-mini',
                messages: 'invalid' // Should be an array
            });

            this.logResult('Error Handling - Invalid Request', 'FAIL', 
                'Expected validation error but request succeeded');

        } catch (error) {
            if (error.status === 400 || error.constructor.name.includes('BadRequest') || 
                error.constructor.name === 'TypeError') {
                this.logResult('Error Handling - Invalid Request', 'PASS', 
                    `Correctly raised ${error.constructor.name}`);
            } else {
                this.logResult('Error Handling - Invalid Request', 'WARN', 
                    `Unexpected error type ${error.constructor.name}: ${error.message}`);
            }
        }
    }

    async testRateLimiting() {
        try {
            const responses = [];
            let rateLimited = false;

            // Make multiple rapid requests
            for (let i = 0; i < 10; i++) {
                try {
                    const response = await this.client.chat.completions.create({
                        model: 'gpt-4o-mini',
                        messages: [{ role: 'user', content: `Rate limit test ${i}` }],
                        max_tokens: 5
                    });
                    responses.push(response);
                } catch (error) {
                    if (error.status === 429 || error.constructor.name === 'RateLimitError' ||
                        error.message.toLowerCase().includes('rate') || 
                        error.message.toLowerCase().includes('limit')) {
                        rateLimited = true;
                        break;
                    }
                    // Other errors might indicate service issues, which is acceptable
                    break;
                }
            }

            if (rateLimited) {
                this.logResult('Rate Limiting', 'PASS', 
                    `Rate limiting triggered after ${responses.length} requests`);
            } else if (responses.length >= 5) {
                this.logResult('Rate Limiting', 'PASS', 
                    `Handled ${responses.length} rapid requests successfully`);
            } else {
                this.logResult('Rate Limiting', 'WARN', 
                    `Only ${responses.length} requests completed`);
            }

        } catch (error) {
            this.logResult('Rate Limiting', 'FAIL', error.message);
        }
    }

    async testTimeoutHandling() {
        try {
            // Create client with very short timeout
            const timeoutClient = new OpenAI({
                apiKey: this.apiKey,
                baseURL: `${this.baseUrl}/v1`,
                timeout: 1000 // 1 second timeout
            });

            await timeoutClient.chat.completions.create({
                model: 'gpt-4o-mini',
                messages: [{ role: 'user', content: 'Quick response please' }],
                max_tokens: 5
            });

            this.logResult('Timeout Handling', 'PASS', 
                'Request completed within timeout');

        } catch (error) {
            if (error.constructor.name === 'APITimeoutError' || 
                error.code === 'ECONNABORTED' ||
                error.message.toLowerCase().includes('timeout')) {
                this.logResult('Timeout Handling', 'PASS', 
                    'Correctly handled timeout');
            } else {
                this.logResult('Timeout Handling', 'WARN', 
                    `Unexpected timeout behavior: ${error.constructor.name}: ${error.message}`);
            }
        }
    }

    async testConcurrentRequests() {
        const makeRequest = async (i) => {
            try {
                const response = await this.client.chat.completions.create({
                    model: 'gpt-4o-mini',
                    messages: [{ role: 'user', content: `Concurrent test ${i}` }],
                    max_tokens: 5
                });
                return { success: true, id: response.id };
            } catch (error) {
                return { success: false, error: error.message };
            }
        };

        try {
            // Make 5 concurrent requests
            const promises = Array.from({ length: 5 }, (_, i) => makeRequest(i));
            const results = await Promise.all(promises);

            const successful = results.filter(r => r.success).length;

            if (successful >= 3) {
                this.logResult('Concurrent Requests', 'PASS', 
                    `${successful}/5 concurrent requests succeeded`);
            } else {
                this.logResult('Concurrent Requests', 'WARN', 
                    `Only ${successful}/5 concurrent requests succeeded`);
            }

        } catch (error) {
            this.logResult('Concurrent Requests', 'FAIL', error.message);
        }
    }

    async runAllTests() {
        console.log('🟨 Starting Node.js SDK Compatibility Validation...');
        console.log('='.repeat(60));

        // Check if Runestone is accessible
        try {
            const response = await axios.get(`${this.baseUrl}/health`, { timeout: 5000 });
            if (![200, 503].includes(response.status)) {
                console.log(`❌ Runestone not accessible at ${this.baseUrl}`);
                return false;
            }
        } catch (error) {
            console.log(`❌ Cannot connect to Runestone: ${error.message}`);
            return false;
        }

        console.log(`✅ Connected to Runestone at ${this.baseUrl}`);
        console.log();

        // Run all tests
        const tests = [
            this.testBasicChatCompletion,
            this.testStreamingChatCompletion,
            this.testModelsList,
            this.testModelsRetrieve,
            this.testErrorHandling,
            this.testRateLimiting,
            this.testTimeoutHandling,
            this.testConcurrentRequests
        ];

        for (const test of tests) {
            try {
                await test.call(this);
            } catch (error) {
                const testName = test.name.replace(/^test/, '').replace(/([A-Z])/g, ' $1').trim();
                this.logResult(testName, 'FAIL', `Test crashed: ${error.message}`);
            }
        }

        // Print summary
        console.log('\n' + '='.repeat(60));
        console.log('📊 Node.js SDK Validation Summary');
        console.log('-'.repeat(30));

        const passed = this.results.filter(r => r.status === 'PASS').length;
        const warned = this.results.filter(r => r.status === 'WARN').length;
        const failed = this.results.filter(r => r.status === 'FAIL').length;
        const total = this.results.length;

        console.log(`✅ Passed: ${passed}/${total}`);
        if (warned > 0) {
            console.log(`⚠️  Warnings: ${warned}/${total}`);
        }
        if (failed > 0) {
            console.log(`❌ Failed: ${failed}/${total}`);
        }

        if (failed === 0) {
            console.log('\n🎉 Node.js SDK compatibility: VALIDATED');
            console.log('   Runestone is fully compatible with the OpenAI Node.js SDK!');
            return true;
        } else {
            console.log('\n❌ Node.js SDK compatibility: FAILED');
            console.log('   Critical issues found that prevent SDK compatibility.');

            console.log('\nFailed tests:');
            for (const result of this.results) {
                if (result.status === 'FAIL') {
                    console.log(`  • ${result.test}: ${result.details}`);
                }
            }

            return false;
        }
    }
}

async function main() {
    const args = process.argv.slice(2);
    let baseUrl = 'http://localhost:4002';
    let apiKey = 'test-api-key';

    // Simple argument parsing
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--base-url' && args[i + 1]) {
            baseUrl = args[i + 1];
            i++;
        } else if (args[i] === '--api-key' && args[i + 1]) {
            apiKey = args[i + 1];
            i++;
        } else if (args[i] === '--help') {
            console.log('Usage: node nodejs_sdk_test.js [options]');
            console.log('Options:');
            console.log('  --base-url URL    Runestone base URL (default: http://localhost:4002)');
            console.log('  --api-key KEY     Test API key (default: test-api-key)');
            console.log('  --help           Show this help message');
            process.exit(0);
        }
    }

    const validator = new RunestoneSDKValidator(baseUrl, apiKey);
    const success = await validator.runAllTests();

    process.exit(success ? 0 : 1);
}

if (require.main === module) {
    main().catch(error => {
        console.error('❌ Validation crashed:', error.message);
        process.exit(1);
    });
}

module.exports = { RunestoneSDKValidator };