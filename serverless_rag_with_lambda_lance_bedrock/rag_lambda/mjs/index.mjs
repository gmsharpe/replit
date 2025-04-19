import fs from 'fs';
import path from 'path';

import { PDFLoader } from "@langchain/community/document_loaders/fs/pdf";
import { RecursiveCharacterTextSplitter } from "@langchain/textsplitters";
import { LanceDB } from '@langchain/community/vectorstores/lancedb';
import { BedrockEmbeddings } from '@langchain/aws';
import { connect } from "vectordb";
import { PromptTemplate } from '@langchain/core/prompts';
import { BedrockChat } from '@langchain/community/chat_models/bedrock';
import { StringOutputParser } from '@langchain/core/output_parsers';
import { RunnableSequence, RunnablePassthrough } from '@langchain/core/runnables';
import { formatDocumentsAsString } from "langchain/util/document";
import { Document } from "@langchain/core/documents";

process.env.AWS_REGION = 'us-west-2';
process.env.DOCS = './serverless_rag_with_lambda_lance_bedrock/rag_lambda/mjs/docs';

let awslambda;
const isLambdaEnv = typeof awslambda !== 'undefined';

const awslambdaShim = isLambdaEnv ? awslambda : {
    streamifyResponse: (handler) => handler,
    HttpResponseStream: {
        from: (stream, metadata) => stream,
    },
};


const LOCAL_DB_PATH = './lancedb'; // local LanceDB folder
const LOCAL_TABLE_NAME = 'doc_table';

async function loadLocalDocuments() {
    const docsDir = path.resolve(process.env.DOCS);
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

const prepareTable = async () => {
    const db = await connect(LOCAL_DB_PATH);
    const tables = await db.tableNames();

    if (tables.includes(LOCAL_TABLE_NAME)) {
        return await db.openTable(LOCAL_TABLE_NAME);
    }

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

    const embeddings = new BedrockEmbeddings({ region: process.env.AWS_REGION });

    console.log("Creating new table from split documents...");
    const vectorStore = await LanceDB.fromDocuments(simplifiedDocs, embeddings, {
        tableName: LOCAL_TABLE_NAME,
        db,
    });

    console.log(`Inserted ${simplifiedDocs.length} chunks into '${LOCAL_TABLE_NAME}'`);
    return vectorStore.table;
};

const runChain = async ({ query, model, streamingFormat }, responseStream) => {
    const table = await prepareTable();
    const embeddings = new BedrockEmbeddings({ region: process.env.AWS_REGION });
    const vectorStore = new LanceDB(embeddings, { table });
    const retriever = vectorStore.asRetriever();

    const prompt = PromptTemplate.fromTemplate(
        `Answer the following question based only on the following context:
        {context}

        Question: {question}`
    );

    const llmModel = new BedrockChat({
        model: model || 'anthropic.claude-instant-v1',
        region: process.env.AWS_REGION,
        streaming: true,
        maxTokens: 1000,
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

    const stream = await chain.stream(query);
    for await (const chunk of stream) {
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

    responseStream.end();
};

function parseBase64(message) {
    if (!message) throw new Error("Invalid input: message is undefined or null");
    return JSON.parse(Buffer.from(message, "base64").toString("utf-8"));
}

export const handler = awslambdaShim.streamifyResponse(async (event, responseStream, _context) => {
    try {
        if (!event || !event.body) throw new Error("Invalid event: body is undefined or null");
        const body = event.isBase64Encoded ? parseBase64(event.body) : JSON.parse(event.body);
        await runChain(body, responseStream);
        console.log(JSON.stringify({ status: "complete" }));
    } catch (error) {
        console.error("Error in handler:", error);
        responseStream.write(JSON.stringify({ error: error.message }));
        responseStream.end();
    }
});
