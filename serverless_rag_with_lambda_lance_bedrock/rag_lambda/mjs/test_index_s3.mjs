import dotenv from 'dotenv';
dotenv.config();

import { describe, it, before, beforeEach } from 'mocha';
import { expect } from 'chai';
import { handler } from './index_s3.mjs';
import { PassThrough } from 'stream';


describe('index_s3.mjs Tests', () => {
  before(async () => {

    // Dynamically import the handler
    const module = await import('./index_s3.mjs');
    const handler = module.handler;
  });

  it('should return the expected result for a valid input', async () => {
    const event = {
      isBase64Encoded: false,
      body: JSON.stringify({ query: "What are the pros and cons to the US Health Care System?",
        model: "anthropic.claude-instant-v1"
       })
    }; // Valid mock event

    const responseStream = new PassThrough(); // Mock response stream
    const context = {}; // Mock context

    const result = await handler(event, responseStream, context);

    expect(result).to.be.an('object');
    expect(result.statusCode).to.equal(200);
    expect(result.body).to.be.a('string');
  });

  it('should handle errors gracefully', async () => {
    const event = null; // Invalid event
    const responseStream = new PassThrough(); // Mock response stream
    const context = {}; // Mock context

    try {
      await handler(event, responseStream, context);
    } catch (error) {
      expect(error).to.be.an('error');
    }
  });

  it('should make an actual call to Bedrock', async () => {
    const event = {
      isBase64Encoded: false,
      body: JSON.stringify({
        query: "What are the pros and cons to the US Health Care System?",
        model: "anthropic.claude-instant-v1",
        //streamingFormat: "fetch-event-source"
      })
    };

    const responseStream = new PassThrough();
    const context = {}; // Mock context

    responseStream.on('data', (chunk) => {
      console.log('Response chunk:', chunk.toString());
    });

    await handler(event, responseStream, context);
  });
});