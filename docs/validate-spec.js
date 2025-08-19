#!/usr/bin/env node

/**
 * OpenAPI Specification Validator for Runestone API
 * 
 * This script validates the OpenAPI specification and performs additional
 * Runestone-specific validation checks.
 */

const fs = require('fs');
const yaml = require('js-yaml');
const path = require('path');

// Colors for console output
const colors = {
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  reset: '\x1b[0m'
};

function log(message, color = 'reset') {
  console.log(colors[color] + message + colors.reset);
}

function validateSpec() {
  const specPath = path.join(__dirname, 'openapi.yaml');
  
  if (!fs.existsSync(specPath)) {
    log('❌ OpenAPI specification file not found at ' + specPath, 'red');
    process.exit(1);
  }

  let spec;
  try {
    spec = yaml.load(fs.readFileSync(specPath, 'utf8'));
    log('✅ YAML specification loaded successfully', 'green');
  } catch (error) {
    log('❌ Failed to parse YAML specification:', 'red');
    console.error(error.message);
    process.exit(1);
  }

  // Basic OpenAPI 3.0 validation
  const validationResults = [];

  // Check OpenAPI version
  if (!spec.openapi || !spec.openapi.startsWith('3.0')) {
    validationResults.push('❌ Invalid or missing OpenAPI version');
  } else {
    validationResults.push('✅ Valid OpenAPI 3.0 specification');
  }

  // Check required fields
  const requiredFields = ['info', 'paths'];
  requiredFields.forEach(field => {
    if (spec[field]) {
      validationResults.push(`✅ Required field '${field}' is present`);
    } else {
      validationResults.push(`❌ Required field '${field}' is missing`);
    }
  });

  // Validate info section
  if (spec.info) {
    const infoRequired = ['title', 'version'];
    infoRequired.forEach(field => {
      if (spec.info[field]) {
        validationResults.push(`✅ Info.${field} is present`);
      } else {
        validationResults.push(`❌ Info.${field} is missing`);
      }
    });
  }

  // Runestone-specific validations
  log('\n🔍 Performing Runestone-specific validations:', 'blue');

  // Check for required Runestone endpoints
  const requiredEndpoints = [
    '/v1/chat/completions',
    '/v1/chat/stream',
    '/v1/models',
    '/health'
  ];

  requiredEndpoints.forEach(endpoint => {
    if (spec.paths && spec.paths[endpoint]) {
      validationResults.push(`✅ Required endpoint '${endpoint}' is documented`);
    } else {
      validationResults.push(`❌ Required endpoint '${endpoint}' is missing`);
    }
  });

  // Check for Runestone-specific schemas
  const requiredSchemas = [
    'CreateChatCompletionRequest',
    'CreateStreamingChatRequest', 
    'QueuedResponse',
    'ErrorResponse'
  ];

  if (spec.components && spec.components.schemas) {
    requiredSchemas.forEach(schema => {
      if (spec.components.schemas[schema]) {
        validationResults.push(`✅ Required schema '${schema}' is present`);
      } else {
        validationResults.push(`❌ Required schema '${schema}' is missing`);
      }
    });
  } else {
    validationResults.push('❌ Components/schemas section is missing');
  }

  // Validate security schemes
  if (spec.components && spec.components.securitySchemes) {
    const securitySchemes = Object.keys(spec.components.securitySchemes);
    if (securitySchemes.length > 0) {
      validationResults.push(`✅ Security schemes defined: ${securitySchemes.join(', ')}`);
    } else {
      validationResults.push('⚠️  No security schemes defined');
    }
  } else {
    validationResults.push('⚠️  No security schemes section found');
  }

  // Check for proper HTTP methods
  const validMethods = ['get', 'post', 'put', 'patch', 'delete', 'options', 'head'];
  if (spec.paths) {
    Object.keys(spec.paths).forEach(path => {
      const pathItem = spec.paths[path];
      Object.keys(pathItem).forEach(method => {
        if (validMethods.includes(method.toLowerCase())) {
          // Check if operation has required fields
          const operation = pathItem[method];
          if (operation.summary && operation.operationId) {
            validationResults.push(`✅ ${method.toUpperCase()} ${path} has summary and operationId`);
          } else {
            validationResults.push(`⚠️  ${method.toUpperCase()} ${path} missing summary or operationId`);
          }
        }
      });
    });
  }

  // Display results
  log('\n📋 Validation Results:', 'blue');
  validationResults.forEach(result => console.log(result));

  // Count errors and warnings
  const errors = validationResults.filter(r => r.includes('❌')).length;
  const warnings = validationResults.filter(r => r.includes('⚠️')).length;
  const successes = validationResults.filter(r => r.includes('✅')).length;

  log(`\n📊 Summary:`, 'blue');
  log(`   ✅ Passed: ${successes}`, 'green');
  log(`   ⚠️  Warnings: ${warnings}`, 'yellow');
  log(`   ❌ Errors: ${errors}`, 'red');

  if (errors > 0) {
    log('\n❌ Validation failed with errors', 'red');
    process.exit(1);
  } else if (warnings > 0) {
    log('\n⚠️  Validation passed with warnings', 'yellow');
  } else {
    log('\n🎉 Validation passed successfully!', 'green');
  }

  // Generate JSON version
  try {
    const jsonPath = path.join(__dirname, 'openapi.json');
    fs.writeFileSync(jsonPath, JSON.stringify(spec, null, 2));
    log(`✅ JSON version generated at ${jsonPath}`, 'green');
  } catch (error) {
    log('⚠️  Failed to generate JSON version:', 'yellow');
    console.error(error.message);
  }
}

// Run validation if called directly
if (require.main === module) {
  log('🚀 Validating Runestone OpenAPI Specification\n', 'blue');
  validateSpec();
}

module.exports = { validateSpec };