import { Router } from 'express';
import pool from '../config/db.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

router.get('/details/:leaderBoardId', async (req, res) => {
  const leaderBoardId = Number(req.params.leaderBoardId);

  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    return res.status(400).json({ message: 'leaderBoardId must be a positive integer' });
  }

  try {
    const [leaderBoardRows] = await pool.query(
      `SELECT
         id,
         name,
         year,
         event_count AS eventCount
       FROM leader_boards
       WHERE id = ?
       LIMIT 1`,
      [leaderBoardId]
    );

    const leaderBoard = leaderBoardRows[0];
    if (!leaderBoard) {
      return res.status(404).json({ message: 'Leader board not found.' });
    }

    const [eventRows] = await pool.query(
      `SELECT
         event_id AS eventId
       FROM leader_board_results
       WHERE leader_board_id = ?
       ORDER BY event_id ASC`,
      [leaderBoardId]
    );

    return res.json({
      leaderBoard,
      eventIds: eventRows.map((row) => Number(row.eventId)).filter((value) => Number.isInteger(value) && value > 0)
    });
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.put('/:leaderBoardId', requireAuth, async (req, res) => {
  const leaderBoardId = Number(req.params.leaderBoardId);
  const name = String(req.body?.name || '').trim();
  const year = Number(req.body?.year);
  const eventIds = Array.isArray(req.body?.eventIds)
    ? [...new Set(req.body.eventIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
    : [];

  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    return res.status(400).json({ message: 'leaderBoardId must be a positive integer' });
  }

  if (!name) {
    return res.status(400).json({ message: 'name is required' });
  }

  if (!Number.isInteger(year) || year <= 0) {
    return res.status(400).json({ message: 'year must be a positive integer' });
  }

  if (eventIds.length === 0) {
    return res.status(400).json({ message: 'At least one selected result is required' });
  }

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [existingRows] = await connection.query(
      `SELECT id
       FROM leader_boards
       WHERE id = ?
       LIMIT 1`,
      [leaderBoardId]
    );

    if (existingRows.length === 0) {
      await connection.rollback();
      return res.status(404).json({ message: 'Leader board not found.' });
    }

    const placeholders = eventIds.map(() => '?').join(', ');
    const [matchingEvents] = await connection.query(
      `SELECT id
       FROM events
       WHERE year = ?
         AND id IN (${placeholders})`,
      [year, ...eventIds]
    );

    if (matchingEvents.length !== eventIds.length) {
      await connection.rollback();
      return res.status(400).json({ message: 'Selected results must belong to the chosen year.' });
    }

    await connection.query(
      `UPDATE leader_boards
       SET
         name = ?,
         year = ?,
         event_count = ?
       WHERE id = ?`,
      [name, year, eventIds.length, leaderBoardId]
    );

    await connection.query(
      `DELETE FROM leader_board_results
       WHERE leader_board_id = ?`,
      [leaderBoardId]
    );

    const valuesPlaceholders = eventIds.map(() => '(?, ?)').join(', ');
    const values = eventIds.flatMap((eventId) => [leaderBoardId, eventId]);

    await connection.query(
      `INSERT INTO leader_board_results (
         leader_board_id,
         event_id
       ) VALUES ${valuesPlaceholders}`,
      values
    );

    const [rows] = await connection.query(
      `SELECT
         id,
         name,
         year,
         event_count AS eventCount
       FROM leader_boards
       WHERE id = ?
       LIMIT 1`,
      [leaderBoardId]
    );

    await connection.commit();

    return res.json({
      message: 'Leader board updated successfully.',
      leaderBoard: rows[0]
    });
  } catch (error) {
    await connection.rollback();
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  } finally {
    connection.release();
  }
});

router.get('/:leaderBoardId/scoreboard', async (req, res) => {
  const leaderBoardId = Number(req.params.leaderBoardId);

  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    return res.status(400).json({ message: 'leaderBoardId must be a positive integer' });
  }

  try {
    const [leaderBoardRows] = await pool.query(
      `SELECT
         id,
         name,
         year,
         event_count AS eventCount
       FROM leader_boards
       WHERE id = ?
       LIMIT 1`,
      [leaderBoardId]
    );

    const leaderBoard = leaderBoardRows[0];
    if (!leaderBoard) {
      return res.status(404).json({ message: 'Leader board not found.' });
    }

    const [rows] = await pool.query(
      `SELECT
         MIN(r.team_name) AS team_name,
         r.team_member,
         COUNT(DISTINCT lbr.event_id) AS event_count,
         SUM(COALESCE(r.final_score_raw, 0)) AS final_score_raw,
         SUM(COALESCE(r.final_score_scaled, 0)) AS final_score_scaled,
         SUM(COALESCE(r.mj_raw, 0)) AS mj_raw,
         SUM(COALESCE(r.mj_scaled, 0)) AS mj_scaled,
         SUM(COALESCE(r.wj_raw, 0)) AS wj_raw,
         SUM(COALESCE(r.wj_scaled, 0)) AS wj_scaled,
         SUM(COALESCE(r.xj_raw, 0)) AS xj_raw,
         SUM(COALESCE(r.xj_scaled, 0)) AS xj_scaled,
         SUM(COALESCE(r.mo_raw, 0)) AS mo_raw,
         SUM(COALESCE(r.mo_scaled, 0)) AS mo_scaled,
         SUM(COALESCE(r.wo_raw, 0)) AS wo_raw,
         SUM(COALESCE(r.wo_scaled, 0)) AS wo_scaled,
         SUM(COALESCE(r.xo_raw, 0)) AS xo_raw,
         SUM(COALESCE(r.xo_scaled, 0)) AS xo_scaled,
         SUM(COALESCE(r.mv_raw, 0)) AS mv_raw,
         SUM(COALESCE(r.mv_scaled, 0)) AS mv_scaled,
         SUM(COALESCE(r.wv_raw, 0)) AS wv_raw,
         SUM(COALESCE(r.wv_scaled, 0)) AS wv_scaled,
         SUM(COALESCE(r.xv_raw, 0)) AS xv_raw,
         SUM(COALESCE(r.xv_scaled, 0)) AS xv_scaled,
         SUM(COALESCE(r.msv_raw, 0)) AS msv_raw,
         SUM(COALESCE(r.msv_scaled, 0)) AS msv_scaled,
         SUM(COALESCE(r.wsv_raw, 0)) AS wsv_raw,
         SUM(COALESCE(r.wsv_scaled, 0)) AS wsv_scaled,
         SUM(COALESCE(r.xsv_raw, 0)) AS xsv_raw,
         SUM(COALESCE(r.xsv_scaled, 0)) AS xsv_scaled,
         SUM(COALESCE(r.muv_raw, 0)) AS muv_raw,
         SUM(COALESCE(r.muv_scaled, 0)) AS muv_scaled,
         SUM(COALESCE(r.wuv_raw, 0)) AS wuv_raw,
         SUM(COALESCE(r.wuv_scaled, 0)) AS wuv_scaled,
         SUM(COALESCE(r.xuv_raw, 0)) AS xuv_raw,
         SUM(COALESCE(r.xuv_scaled, 0)) AS xuv_scaled
       FROM leader_board_results lbr
       INNER JOIN results r ON r.event_id = lbr.event_id
       WHERE lbr.leader_board_id = ?
       GROUP BY r.team_member
       ORDER BY r.team_member ASC`,
      [leaderBoardId]
    );

    return res.json({
      leaderBoard,
      rows
    });
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.get('/:leaderBoardId/events', async (req, res) => {
  const leaderBoardId = Number(req.params.leaderBoardId);

  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    return res.status(400).json({ message: 'leaderBoardId must be a positive integer' });
  }

  try {
    const [leaderBoardRows] = await pool.query(
      `SELECT id FROM leader_boards WHERE id = ? LIMIT 1`,
      [leaderBoardId]
    );

    if (leaderBoardRows.length === 0) {
      return res.status(404).json({ message: 'Leader board not found.' });
    }

    const [rows] = await pool.query(
      `SELECT
         e.id,
         e.name,
         e.series,
         e.year,
         DATE_FORMAT(e.date, '%Y-%m-%d') AS date,
         e.organiser,
         e.duration_hours AS durationHours
       FROM leader_board_results lbr
       INNER JOIN events e ON e.id = lbr.event_id
       WHERE lbr.leader_board_id = ?
       ORDER BY e.date ASC, e.name ASC, e.id ASC`,
      [leaderBoardId]
    );

    return res.json(rows);
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.get('/:leaderBoardId/member-events', async (req, res) => {
  const leaderBoardId = Number(req.params.leaderBoardId);
  const member = String(req.query?.member || '').trim();

  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    return res.status(400).json({ message: 'leaderBoardId must be a positive integer' });
  }

  if (!member) {
    return res.status(400).json({ message: 'member query parameter is required' });
  }

  try {
    const [rows] = await pool.query(
      `SELECT
         e.id AS eventId,
         e.name AS eventName,
         e.series,
         DATE_FORMAT(e.date, '%Y-%m-%d') AS date,
         r.team_name AS teamName,
         r.team_member AS teamMember,
         r.final_score_raw AS finalScoreRaw,
         r.final_score_scaled AS finalScoreScaled,
         r.mj_raw AS mjRaw,
         r.mj_scaled AS mjScaled,
         r.wj_raw AS wjRaw,
         r.wj_scaled AS wjScaled,
         r.xj_raw AS xjRaw,
         r.xj_scaled AS xjScaled,
         r.mo_raw AS moRaw,
         r.mo_scaled AS moScaled,
         r.wo_raw AS woRaw,
         r.wo_scaled AS woScaled,
         r.xo_raw AS xoRaw,
         r.xo_scaled AS xoScaled,
         r.mv_raw AS mvRaw,
         r.mv_scaled AS mvScaled,
         r.wv_raw AS wvRaw,
         r.wv_scaled AS wvScaled,
         r.xv_raw AS xvRaw,
         r.xv_scaled AS xvScaled,
         r.msv_raw AS msvRaw,
         r.msv_scaled AS msvScaled,
         r.wsv_raw AS wsvRaw,
         r.wsv_scaled AS wsvScaled,
         r.xsv_raw AS xsvRaw,
         r.xsv_scaled AS xsvScaled,
         r.muv_raw AS muvRaw,
         r.muv_scaled AS muvScaled,
         r.wuv_raw AS wuvRaw,
         r.wuv_scaled AS wuvScaled,
         r.xuv_raw AS xuvRaw,
         r.xuv_scaled AS xuvScaled
       FROM leader_board_results lbr
       INNER JOIN results r ON r.event_id = lbr.event_id
       INNER JOIN events e ON e.id = r.event_id
       WHERE lbr.leader_board_id = ?
         AND r.team_member = ?
       ORDER BY e.date ASC, e.name ASC, e.id ASC`,
      [leaderBoardId, member]
    );

    return res.json(rows);
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.get('/year-results', async (req, res) => {
  const year = Number(req.query?.year);

  if (!Number.isInteger(year) || year <= 0) {
    return res.status(400).json({ message: 'year query parameter must be a positive integer' });
  }

  try {
    const [rows] = await pool.query(
      `SELECT
         id,
         name,
         series,
         DATE_FORMAT(date, '%Y-%m-%d') AS date
       FROM events
       WHERE year = ?
       ORDER BY date ASC, name ASC, id ASC`,
      [year]
    );

    return res.json(rows);
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'events table does not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

router.post('/', async (req, res) => {
  const name = String(req.body?.name || '').trim();
  const year = Number(req.body?.year);
  const eventIds = Array.isArray(req.body?.eventIds)
    ? [...new Set(req.body.eventIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
    : [];

  if (!name) {
    return res.status(400).json({ message: 'name is required' });
  }

  if (!Number.isInteger(year) || year <= 0) {
    return res.status(400).json({ message: 'year must be a positive integer' });
  }

  if (eventIds.length === 0) {
    return res.status(400).json({ message: 'At least one selected result is required' });
  }

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const placeholders = eventIds.map(() => '?').join(', ');
    const [matchingEvents] = await connection.query(
      `SELECT id
       FROM events
       WHERE year = ?
         AND id IN (${placeholders})`,
      [year, ...eventIds]
    );

    if (matchingEvents.length !== eventIds.length) {
      await connection.rollback();
      return res.status(400).json({ message: 'Selected results must belong to the chosen year.' });
    }

    const [insertResult] = await connection.query(
      `INSERT INTO leader_boards (
         name,
         year,
         event_count
       ) VALUES (?, ?, ?)`,
      [name, year, eventIds.length]
    );

    const leaderBoardId = insertResult.insertId;

    const valuesPlaceholders = eventIds.map(() => '(?, ?)').join(', ');
    const values = eventIds.flatMap((eventId) => [leaderBoardId, eventId]);

    await connection.query(
      `INSERT INTO leader_board_results (
         leader_board_id,
         event_id
       ) VALUES ${valuesPlaceholders}`,
      values
    );

    const [rows] = await connection.query(
      `SELECT
         id,
         name,
         year,
         event_count AS eventCount
       FROM leader_boards
       WHERE id = ?
       LIMIT 1`,
      [leaderBoardId]
    );

    await connection.commit();

    return res.status(201).json({
      message: 'Leader board created successfully.',
      leaderBoard: rows[0]
    });
  } catch (error) {
    await connection.rollback();
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'Required tables do not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  } finally {
    connection.release();
  }
});

router.get('/', async (_req, res) => {
  try {
    const [rows] = await pool.query(
      `SELECT
         id,
         name,
         year,
         event_count AS eventCount
       FROM leader_boards
       ORDER BY year DESC, name ASC, id ASC`
    );

    return res.json(rows);
  } catch (error) {
    if (error.code === 'ER_NO_SUCH_TABLE') {
      return res.status(500).json({
        message: 'leader_boards table does not exist. Run backend/sql/init.sql first.'
      });
    }

    return res.status(500).json({ message: error.message });
  }
});

export default router;
