import express from 'express';
import cors from 'cors';
import healthRouter from './routes/health.js';
import usersRouter from './routes/users.js';
import eventsRouter from './routes/events.js';
import jsonLoaderRouter from './routes/json-loader.js';
import leaderBoardsRouter from './routes/leader-boards.js';
import authRouter from './routes/auth.js';
import categoryMappingsRouter from './routes/category-mappings.js';

const app = express();
const jsonBodyLimit = process.env.JSON_BODY_LIMIT || '10mb';

app.use(cors());
app.use(express.json({ limit: jsonBodyLimit }));

app.get('/', (_req, res) => {
  res.json({ message: 'Rogainizer API is running' });
});

app.use('/api/health', healthRouter);
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);
app.use('/api/events', eventsRouter);
app.use('/api/json-loader', jsonLoaderRouter);
app.use('/api/leader-boards', leaderBoardsRouter);
app.use('/api/category-mappings', categoryMappingsRouter);

export default app;
