import { LanceDB } from '@langchain/community/vectorstores/lancedb';
import { BedrockEmbeddings } from '@langchain/aws';
import { connect } from "@lancedb/lancedb"; // LanceDB
import { PromptTemplate } from '@langchain/core/prompts';
import { BedrockChat } from '@langchain/community/chat_models/bedrock';
import { StringOutputParser } from '@langchain/core/output_parsers';
import { RunnableSequence, RunnablePassthrough } from '@langchain/core/runnables';
import { formatDocumentsAsString } from "langchain/util/document";

import { Document } from "@langchain/core/documents";
import { PDFLoader } from "@langchain/community/document_loaders/fs/pdf";
import { RecursiveCharacterTextSplitter } from "@langchain/textsplitters";
import { Schema, Field, Float32, FixedSizeList, Utf8, Struct } from 'apache-arrow';
import fs from 'fs';
import path from 'path';

const lanceDbSrc = process.env.s3BucketName;
const lanceDbTable = process.env.lanceDbTable;
const awsRegion = process.env.region;
const useS3 = process.env.useS3 === 'true';
const uploadEmbeddings = process.env.uploadEmbeddings === 'true';

if (typeof awslambda === 'undefined') {
    global.awslambda = {
        streamifyResponse: (handler) => handler,
        HttpResponseStream: {
            from: (stream, metadata) => stream,
        },
    };
}

async function loadLocalDocuments(docsDirStr = './serverless_rag_with_lambda_lance_bedrock/rag_lambda/mjs/docs') {
    const docsDir = path.resolve(docsDirStr);
    const docs = [];

    if (!fs.existsSync(docsDir)) {
        throw new Error(`docs/ directory not found at: ${docsDir}`);
    }

    const files = fs.readdirSync(docsDir);

    for (const file of files) {
        const filePath = path.join(docsDir, file);

        if (file.endsWith(".pdf")) {
            const loader = new PDFLoader(filePath, {
                splitPages: false,
                parsedItemSeparator: "", // prevents extra spaces
            });
            const pdfDocs = await loader.load();
            docs.push(...pdfDocs);
        } else {
            const content = fs.readFileSync(filePath, 'utf-8');
            docs.push(new Document({ pageContent: content, metadata: { source: file } }));
        }
    }

    return docs;
}

const runChain = async ({ query, model, streamingFormat }, responseStream, awsRegion, useS3, uploadEmbeddings, lanceDbSrc, lanceDbTable) => {
    const dbUri = useS3 ? `s3://${lanceDbSrc}/${lanceDbTable}/` : 'tmp/embeddings';

    const db = await connect({
        uri: dbUri,
        region: awsRegion
    }

    );

    let vectorStore;

    if (uploadEmbeddings) {
        console.log('Uploading embeddings to', dbUri);
        // Logic to create and upload embeddings to S3 or locally
        const docs = await loadLocalDocuments();
        if (docs.length === 0) {
            throw new Error("No documents found. Cannot create a LanceDB table without data.");
        }

        // ✅ Add this step to chunk large documents
        const splitter = new RecursiveCharacterTextSplitter({
            chunkSize: 1000,       // Safe for most embedding models
            chunkOverlap: 200,     // Adds continuity across chunks
        });

        const splitDocs = await splitter.splitDocuments(docs);

        // Remove metadata from split documents
        // This is optional, but if you want to keep the original metadata, you can do this:
        const simplifiedDocs = splitDocs.map(doc =>
            new Document({ pageContent: doc.pageContent, metadata: {} })
        );

        const embeddings = new BedrockEmbeddings({
            region: awsRegion,
            model: 'amazon.titan-embed-text-v1',
        });
        // type LanceDBArgs = {
        //     table?: Table;
        //     textKey?: string;
        //     uri?: string;
        //     tableName?: string;
        //     mode?: "create" | "overwrite";
        // }

        const data = await Promise.all(
            simplifiedDocs.map(async (doc, index) => {
              const vector = await embeddings.embedQuery(doc.pageContent);
          
            //   const text = String(doc.pageContent ?? "").trim();

            //   const sanitizeText = (input) => {
            //     return text.replace(/[\u0000-\u001F\u007F-\u009F]/g, ' ').trim();
            //   };

            //   if (!sanitizeText) {
            //     console.warn(`⚠️ Skipping empty document at index ${index}`);
            //     return null;
            //   }

              return {
                vector: vector,
                text: String(doc.pageContent ?? ""),    // ensure it's a string
                id: index,                     // force string
                metadata: {}                           // keep this simple for now
              };
            })
          );

        // https://js.langchain.com/docs/integrations/vectorstores/lancedb/

        console.log("Creating new table from split documents...");

        vectorStore = await LanceDB.fromDocuments(simplifiedDocs, embeddings, {
            uri: dbUri,
            tableName: lanceDbTable,
            mode: 'overwrite',
          });
        
          console.log(`✅ Embeddings stored at ${dbUri}`);
        
          // Validate
          const testDocs = await vectorStore.asRetriever().getRelevantDocuments('hello world');
          console.log(`🔍 Retrieval test returned ${testDocs.length} document(s)`);

        // const table = await db.createTable(lanceDbTable, data, { 
        //     mode: "overwrite",
        //     storageOptions : 
        //     { 
        //         aws_region: awsRegion
        //     } 
        // });

        //console.log(`Number of rows in table: ${await table.countRows()}`);

        //const table = await db.createTable(lanceDbTable, simplifiedDocs);
        // vectorStore = await LanceDB.fromDocuments(simplifiedDocs, embeddings, {
        //     tableName: lanceDbTable,
        //     uri: dbUri,
        //     mode: "overwrite",
        //   }
        // );
        //table.vectorStore
        // vectorStore = new LanceDB(embeddings, {
        //     table,
        //     //     private table?;
        //     uri: dbUri,
        //     tableName: lanceDbTable,
        //     textKey: "text",     // column that contains document text
        //     vectorKey: "vector", // column that contains embedding vector
        //   });

        console.log('Embeddings uploaded successfully');
    } else {
        console.log('Reading from table at', dbUri);
        const table = await db.openTable(lanceDbTable);
        vectorStore = new LanceDB(embeddings, { table });
    }

    const retriever = vectorStore.asRetriever();

    const test = await vectorStore.asRetriever().getRelevantDocuments("hello");
    console.log("Retriever returned:", test.length);

    const prompt = PromptTemplate.fromTemplate(
        `Answer the following question based only on the following context:
        {context}

        Question: {question}`
    );

    const llmModel = new BedrockChat({
        model: model || 'anthropic.claude-instant-v1',
        region: awsRegion,
        streaming: true,
        maxTokens: 5000,
    });


    const chain = RunnableSequence.from([
        {
            context: retriever.pipe(formatDocumentsAsString),
            question: new RunnablePassthrough()
        },
        prompt,
        llmModel,
        new StringOutputParser()
    ]);

    let fullOutput = '';
    const stream = await chain.stream(query);
    for await (const chunk of stream) {
        fullOutput += chunk;
        switch (streamingFormat) {
            case 'fetch-event-source':
                responseStream.write(`event: message\n`);
                responseStream.write(`data: ${chunk}\n\n`);
                break;
            default:
                responseStream.write(chunk);
                break;
        }
    }
    console.log("Final response:\n", fullOutput);

    responseStream.end();
};

function parseBase64(message) {
    if (!message) {
        throw new Error("Invalid input: message is undefined or null");
    }
    return JSON.parse(Buffer.from(message, "base64").toString("utf-8"));
}

export const handler = awslambda.streamifyResponse(async (event, responseStream, _context) => {
    try {

        console.log('Environment Variables in index_s3.mjs:', {
            s3BucketName: process.env.s3BucketName,
            lanceDbTable: process.env.lanceDbTable,
            region: process.env.region,
            useS3: process.env.useS3,
            uploadEmbeddings: process.env.uploadEmbeddings,
        });

        const lanceDbSrc = process.env.s3BucketName;
        const lanceDbTable = process.env.lanceDbTable;
        const awsRegion = process.env.region;
        const useS3 = process.env.useS3 === 'true';
        const uploadEmbeddings = process.env.uploadEmbeddings === 'true';

        if (!event || !event.body) {
            throw new Error("Invalid event: body is undefined or null");
        }
        const body = event.isBase64Encoded ? parseBase64(event.body) : JSON.parse(event.body);
        await runChain(body, responseStream, awsRegion, useS3, uploadEmbeddings, lanceDbSrc, lanceDbTable);
        console.log(JSON.stringify({ "status": "complete" }));
    } catch (error) {
        console.error("Error in handler:", error);
        responseStream.write(JSON.stringify({ error: error.message }));
        responseStream.end();
    }
});