<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import JsonTreeNode from './components/JsonTreeNode.vue';

const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3000';
const weightingTableConfig = import.meta.env.VITE_SCALE_WEIGHTING_TABLE || '';
const loginStorageKey = 'rogainizer-login-token';

function parseWeightingTable(rawTable) {
  const defaultTable = [
    { duration: 24, weighting: 1.2 },
    { duration: 12, weighting: 1.0 },
    { duration: 6, weighting: 0.8 },
    { duration: 3, weighting: 0.6 },
    { duration: 2, weighting: 0.5 },
    { duration: 0, weighting: 0.3 }
  ];

  const raw = String(rawTable || '').trim();
  if (!raw) {
    return defaultTable;
  }

  const parsed = raw
    .split(/\s*[;|\n]\s*/)
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const parts = entry.split(/[,:]/).map((part) => part.trim()).filter(Boolean);
      if (parts.length < 2) {
        return null;
      }

      const duration = Number(parts[0]);
      const weighting = Number(parts[1]);

      if (!Number.isFinite(duration) || !Number.isFinite(weighting)) {
        return null;
      }

      return { duration, weighting };
    })
    .filter(Boolean);

  return parsed.length > 0 ? parsed : defaultTable;
}

const weightingTable = parseWeightingTable(weightingTableConfig);
const currentView = ref('leader-boards');
const jsonLoadErrorMessage = ref('');
const jsonLoadData = ref(null);
const jsonLoadLoading = ref(false);
const saveEventLoading = ref(false);
const saveEventErrorMessage = ref('');
const saveEventSuccessMessage = ref('');
const savedEventId = ref(null);
const saveTransformedLoading = ref(false);
const saveTransformedErrorMessage = ref('');
const saveTransformedSuccessMessage = ref('');
const eventsIndex = ref([]);
const eventsIndexLoading = ref(false);
const eventsIndexErrorMessage = ref('');
const selectedEventYear = ref('');
const selectedEventSeries = ref('');
const selectedEventTitle = ref('');
const transformErrorMessage = ref('');
const transformedRows = ref([]);
const transformedColumns = ref([]);
const transformedDisplayMode = ref('raw');
const showCategoryMappingDialog = ref(false);
const categoryMappingRows = ref([]);
const categoryMappingErrorMessage = ref('');
const fixedCategoryColumns = ['MJ', 'WJ', 'XJ', 'MO', 'WO', 'XO', 'MV', 'WV', 'XV', 'MSV', 'WSV', 'XSV', 'MUV', 'WUV', 'XUV'];
const leaderBoards = ref([]);
const leaderBoardsLoading = ref(false);
const leaderBoardsErrorMessage = ref('');
const activeLeaderBoard = ref(null);
const leaderBoardScoresRows = ref([]);
const leaderBoardScoresLoading = ref(false);
const leaderBoardScoresErrorMessage = ref('');
const leaderBoardScoresShowRaw = ref(false);
const leaderBoardScoresShowRank = ref(false);
const leaderBoardScoreSortColumn = ref('final_score');
const leaderBoardScoreSortDirection = ref('desc');
const showLeaderBoardMemberDialog = ref(false);
const selectedLeaderBoardMember = ref('');
const leaderBoardMemberEventRows = ref([]);
const leaderBoardMemberEventsLoading = ref(false);
const leaderBoardMemberEventsErrorMessage = ref('');
const showCreateLeaderBoardDialog = ref(false);
const createLeaderBoardLoading = ref(false);
const createLeaderBoardErrorMessage = ref('');
const createLeaderBoardSuccessMessage = ref('');
const newLeaderBoardName = ref('');
const newLeaderBoardYear = ref('');
const leaderBoardYearResults = ref([]);
const leaderBoardYearResultsLoading = ref(false);
const leaderBoardYearResultsErrorMessage = ref('');
const selectedLeaderBoardResultIds = ref([]);
const resultsEvents = ref([]);
const resultsEventsLoading = ref(false);
const resultsEventsErrorMessage = ref('');
const selectedResultsEventId = ref('');
const selectedResultsEvent = ref(null);
const eventResultsRows = ref([]);
const eventResultsLoading = ref(false);
const eventResultsErrorMessage = ref('');
const eventResultsDisplayMode = ref('scaled');
const showOnlyFlaggedResultMembers = ref(false);
const showEditResultDialog = ref(false);
const editResultId = ref(null);
const editResultTeamName = ref('');
const editResultTeamMember = ref('');
const editResultLoading = ref(false);
const editResultErrorMessage = ref('');
const showEditLeaderBoardDialog = ref(false);
const editLeaderBoardId = ref(null);
const editLeaderBoardLoading = ref(false);
const editLeaderBoardLoadingDetails = ref(false);
const editLeaderBoardErrorMessage = ref('');
const editLeaderBoardName = ref('');
const editLeaderBoardYear = ref('');
const editLeaderBoardYearResults = ref([]);
const editLeaderBoardYearResultsLoading = ref(false);
const editLeaderBoardYearResultsErrorMessage = ref('');
const selectedEditLeaderBoardResultIds = ref([]);
const showLeaderBoardEventsDialog = ref(false);
const leaderBoardEvents = ref([]);
const leaderBoardEventsLoading = ref(false);
const leaderBoardEventsErrorMessage = ref('');
const leaderBoardEventsTitle = ref('');
const showLeaderBoardHelpDialog = ref(false);
const isLoggedIn = ref(false);
const authToken = ref('');
const showLoginDialog = ref(false);
const loginUsernameInput = ref('');
const loginPasswordInput = ref('');
const loginErrorMessage = ref('');
const loginSubmitting = ref(false);

const filteredEventSeries = computed(() => {
  const targetYear = String(selectedEventYear.value || '').trim();
  if (!targetYear) {
    return [];
  }

  return [...new Set(
    eventsIndex.value
      .filter((item) => String(item?.eventYear ?? '').trim() === targetYear)
      .map((item) => String(item?.eventSeries || '').trim())
      .filter(Boolean)
  )].sort((left, right) => left.localeCompare(right));
});

const filteredEvents = computed(() => {
  const targetYear = String(selectedEventYear.value || '').trim();
  const targetSeries = String(selectedEventSeries.value || '').trim();

  if (!targetYear || !targetSeries) {
    return [];
  }

  const matchingSeries = eventsIndex.value.filter(
    (item) =>
      String(item?.eventYear ?? '').trim() === targetYear
      && String(item?.eventSeries || '').trim() === targetSeries
  );

  return matchingSeries
    .flatMap((item, seriesIndex) =>
      (Array.isArray(item?.events) ? item.events : []).map((eventItem, eventIndex) => ({
        key: `${seriesIndex}-${eventIndex}-${String(eventItem?.eventTitle || eventItem?.eventName || '').trim()}`,
        title: String(eventItem?.eventTitle || eventItem?.eventName || '').trim(),
        eventName: String(eventItem?.eventName || '').trim(),
        eventCourse: String(eventItem?.eventCourse || '').trim(),
        path: String(eventItem?.path || '').trim()
      }))
    )
    .filter((eventItem) => Boolean(eventItem.title));
});

const selectedEventDetails = computed(() =>
  filteredEvents.value.find((eventItem) => eventItem.key === selectedEventTitle.value) || null
);

const selectedEventResultsUrl = computed(() => {
  const year = String(selectedEventYear.value || '').trim();
  const details = selectedEventDetails.value;

  if (!year || !details) {
    return '';
  }

  const toSlug = (value) =>
    String(value || '')
      .trim()
      .toLowerCase()
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-');

  const hasEventCourse = Boolean(String(details.eventCourse || '').trim());

  const eventNameSource = hasEventCourse
      ? `${selectedEventSeries.value}/${details.eventName}`
      : selectedEventSeries.value;

  const eventCourseSource = hasEventCourse
    ? details.eventCourse
    : details.eventName;

  const eventNameSlug = toSlug(eventNameSource);
  const eventCourseSlug = toSlug(eventCourseSource);

  if (!eventNameSlug || !eventCourseSlug) {
    return '';
  }

  return `https://rogaine-results.com/${year}/${eventNameSlug}/${eventCourseSlug}/results.json`;
});

const scaledColumns = computed(() =>
  transformedColumns.value.filter((column) => column !== 'team_name' && column !== 'team_member')
);

const scaledColumnMax = computed(() => {
  const maxByColumn = {};

  for (const column of scaledColumns.value) {
    let maxValue = 0;

    for (const row of transformedRows.value) {
      const numericValue = Number(row[column]);
      if (Number.isFinite(numericValue) && numericValue > maxValue) {
        maxValue = numericValue;
      }
    }

    maxByColumn[column] = maxValue;
  }

  return maxByColumn;
});

const scaledRows = computed(() =>
  transformedRows.value.map((row) => {
    const scaledRow = { ...row };

    for (const column of scaledColumns.value) {
      const maxValue = scaledColumnMax.value[column];
      const numericValue = Number(row[column]);

      if (!Number.isFinite(numericValue)) {
        scaledRow[column] = row[column];
      } else if (numericValue === 0) {
        scaledRow[column] = '';
      } else if (maxValue > 0) {
        const percentage = (numericValue / maxValue) * 100;
        const weightedPercentage = percentage * selectedDurationWeighting.value;
        scaledRow[column] = Math.ceil(weightedPercentage);
      } else {
        scaledRow[column] = '';
      }
    }

    return scaledRow;
  })
);

const displayedTransformedRows = computed(() =>
  transformedDisplayMode.value === 'scaled' ? scaledRows.value : transformedRows.value
);

const leaderBoardScoreColumns = computed(() => ['team_member', 'event_count', 'final_score', ...fixedCategoryColumns]);
const eventResultsColumns = computed(() => ['team_name', 'team_member', 'final_score', ...fixedCategoryColumns]);

const displayedLeaderBoardScoreRows = computed(() =>
  leaderBoardScoresRows.value.map((row) => {
    const modeValues = row[leaderBoardScoresShowRaw.value ? 'raw' : 'scaled'] || {};
    return {
      team_name: row.team_name,
      team_member: row.team_member,
      ...modeValues
    };
  })
);

const leaderBoardScoreRanks = computed(() => {
  const rankByColumn = {};
  const rows = displayedLeaderBoardScoreRows.value;

  for (const column of leaderBoardScoreColumns.value) {
    if (!isLeaderBoardScoreColumn(column) || column === 'event_count') {
      continue;
    }

    const values = rows
      .map((row) => ({
        member: String(row.team_member || ''),
        value: Number(row[column] ?? 0)
      }))
      .filter((item) => Number.isFinite(item.value) && item.value > 0)
      .sort((left, right) => right.value - left.value);

    const columnRanks = {};
    let previousValue = null;
    let previousRank = 0;

    values.forEach((item, index) => {
      const currentRank = previousValue === item.value ? previousRank : index + 1;
      if (!(item.member in columnRanks)) {
        columnRanks[item.member] = currentRank;
      }
      previousValue = item.value;
      previousRank = currentRank;
    });

    rankByColumn[column] = columnRanks;
  }

  return rankByColumn;
});

const sortedLeaderBoardScoreRows = computed(() => {
  const items = [...displayedLeaderBoardScoreRows.value];
  const sortColumn = leaderBoardScoreSortColumn.value;
  const direction = leaderBoardScoreSortDirection.value === 'asc' ? 1 : -1;

  items.sort((left, right) => {
    if (sortColumn === 'team_name' || sortColumn === 'team_member') {
      const leftValue = String(left[sortColumn] || '').toLowerCase();
      const rightValue = String(right[sortColumn] || '').toLowerCase();
      return leftValue.localeCompare(rightValue) * direction;
    }

    const leftValue = Number(left[sortColumn] ?? 0);
    const rightValue = Number(right[sortColumn] ?? 0);
    return (leftValue - rightValue) * direction;
  });

  return items;
});

const displayedEventResultsRows = computed(() =>
  eventResultsRows.value.map((row) => {
    const modeValues = row[eventResultsDisplayMode.value] || {};
    return {
      id: row.id,
      team_name: row.team_name,
      team_member: row.team_member,
      ...modeValues
    };
  })
);

const filteredEventResultsRows = computed(() => {
  if (!showOnlyFlaggedResultMembers.value) {
    return displayedEventResultsRows.value;
  }

  return displayedEventResultsRows.value.filter((row) => shouldHighlightMemberName(row.team_member));
});

const selectedEventDuration = computed(() => {
  const duration = Number(jsonLoadData.value?.event_duration);
  return Number.isFinite(duration) ? duration : null;
});

const selectedDurationWeighting = computed(() => {
  const duration = selectedEventDuration.value;
  if (duration === null) {
    return 1;
  }

  for (const item of weightingTable) {
    if (duration >= item.duration) {
      return item.weighting;
    }
  }

  return weightingTable.at(-1)?.weighting ?? 1;
});

watch(filteredEventSeries, (options) => {
  if (!options.includes(selectedEventSeries.value)) {
    selectedEventSeries.value = '';
  }
});

watch(filteredEvents, (options) => {
  if (!options.some((eventItem) => eventItem.key === selectedEventTitle.value)) {
    selectedEventTitle.value = '';
  }
});

watch(newLeaderBoardYear, () => {
  if (showCreateLeaderBoardDialog.value) {
    fetchLeaderBoardYearResults();
  }
});

watch(editLeaderBoardYear, () => {
  if (showEditLeaderBoardDialog.value && !editLeaderBoardLoadingDetails.value) {
    fetchEditLeaderBoardYearResults();
  }
});

function transformedColumnLabel(column) {
  if (column === 'team_name') {
    return 'Team';
  }

  if (column === 'team_member') {
    return 'Member';
  }

  if (column === 'final_score') {
    return 'Score';
  }

  if (column === 'event_count') {
    return 'Events';
  }

  return column;
}

function isLeaderBoardScoreColumn(column) {
  return column !== 'team_name' && column !== 'team_member';
}

function sortLeaderBoardScoresBy(column) {
  if (!isLeaderBoardScoreColumn(column)) {
    return;
  }

  if (leaderBoardScoreSortColumn.value === column) {
    leaderBoardScoreSortDirection.value = leaderBoardScoreSortDirection.value === 'asc' ? 'desc' : 'asc';
    return;
  }

  leaderBoardScoreSortColumn.value = column;
  leaderBoardScoreSortDirection.value = 'desc';
}

function leaderBoardSortIndicator(column) {
  if (leaderBoardScoreSortColumn.value !== column) {
    return '';
  }

  return leaderBoardScoreSortDirection.value === 'asc' ? ' ▲' : ' ▼';
}

function leaderBoardColumnLabel(column) {
  if (column === 'team_member') {
    return ' ';
  }

  return transformedColumnLabel(column);
}

function formatLeaderBoardScoreCell(row, column) {
  if (column === 'team_member') {
    return row[column];
  }

  if (column === 'event_count') {
    const numericValue = Number(row[column] ?? 0);
    return Number.isFinite(numericValue) ? numericValue : 0;
  }

  if (isLeaderBoardScoreColumn(column)) {
    const numericValue = Number(row[column]);
    if (!Number.isFinite(numericValue) || numericValue === 0) {
      return ' ';
    }

    if (leaderBoardScoresShowRank.value) {
      const member = String(row.team_member || '');
      const rank = Number(leaderBoardScoreRanks.value?.[column]?.[member] ?? 0);
      return Number.isFinite(rank) && rank > 0 ? rank : ' ';
    }
  }

  return row[column];
}

function closeLeaderBoardMemberDialog() {
  showLeaderBoardMemberDialog.value = false;
  selectedLeaderBoardMember.value = '';
  leaderBoardMemberEventRows.value = [];
  leaderBoardMemberEventsErrorMessage.value = '';
}

function eventRowCategoriesText(eventRow) {
  const mode = leaderBoardScoresShowRaw.value ? 'raw' : 'scaled';
  const modeSuffix = mode === 'scaled' ? 'Scaled' : 'Raw';

  return fixedCategoryColumns
    .map((category) => {
      const fieldName = `${category.toLowerCase()}${modeSuffix}`;
      const numericValue = Number(eventRow?.[fieldName] ?? 0);
      if (!Number.isFinite(numericValue) || numericValue === 0) {
        return '';
      }
      return `${category}: ${numericValue}`;
    })
    .filter(Boolean)
    .join(', ');
}

function eventRowScoreValue(eventRow) {
  const fieldName = leaderBoardScoresShowRaw.value ? 'finalScoreRaw' : 'finalScoreScaled';
  const numericValue = Number(eventRow?.[fieldName] ?? 0);

  if (!Number.isFinite(numericValue) || numericValue === 0) {
    return ' ';
  }

  return numericValue;
}

async function openLeaderBoardMemberDialog(row) {
  if (!activeLeaderBoard.value?.id) {
    return;
  }

  const memberName = String(row?.team_member || '').trim();
  if (!memberName) {
    return;
  }

  selectedLeaderBoardMember.value = memberName;
  leaderBoardMemberEventRows.value = [];
  leaderBoardMemberEventsErrorMessage.value = '';
  leaderBoardMemberEventsLoading.value = true;
  showLeaderBoardMemberDialog.value = true;

  try {
    const query = new URLSearchParams({ member: memberName });
    const response = await fetch(`${apiBaseUrl}/api/leader-boards/${activeLeaderBoard.value.id}/member-events?${query.toString()}`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load member event scores');
    }

    const data = await response.json();
    leaderBoardMemberEventRows.value = Array.isArray(data) ? data : [];
  } catch (error) {
    leaderBoardMemberEventsErrorMessage.value = error.message || 'Failed to load member event scores';
  } finally {
    leaderBoardMemberEventsLoading.value = false;
  }
}

function formatDurationHours(value) {
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) {
    return '';
  }

  return String(parseFloat(numericValue.toFixed(2)));
}

async function openLeaderBoardEventsDialog(leaderBoard) {
  const leaderBoardId = Number(leaderBoard?.id);
  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    return;
  }

  leaderBoardEventsTitle.value = String(leaderBoard?.name || '');
  leaderBoardEvents.value = [];
  leaderBoardEventsErrorMessage.value = '';
  leaderBoardEventsLoading.value = true;
  showLeaderBoardEventsDialog.value = true;

  try {
    const response = await fetch(`${apiBaseUrl}/api/leader-boards/${leaderBoardId}/events`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load leader board events');
    }

    const data = await response.json();
    leaderBoardEvents.value = Array.isArray(data) ? data : [];
  } catch (error) {
    leaderBoardEventsErrorMessage.value = error.message || 'Failed to load leader board events';
  } finally {
    leaderBoardEventsLoading.value = false;
  }
}

function closeLeaderBoardEventsDialog() {
  showLeaderBoardEventsDialog.value = false;
  leaderBoardEvents.value = [];
  leaderBoardEventsErrorMessage.value = '';
  leaderBoardEventsTitle.value = '';
}

function switchView(view) {
  if (view === 'json-loader' && !isLoggedIn.value) {
    openLoginDialog();
    return;
  }

  currentView.value = view;

  if (view === 'leader-boards') {
    fetchLeaderBoards();
  }

  if (view === 'results') {
    fetchResultsEvents();
  }
}

function openLoginDialog() {
  loginErrorMessage.value = '';
  loginUsernameInput.value = '';
  loginPasswordInput.value = '';
  showLoginDialog.value = true;
}

function closeLoginDialog() {
  showLoginDialog.value = false;
  loginErrorMessage.value = '';
}

async function submitLogin() {
  if (loginSubmitting.value) {
    return;
  }

  const username = String(loginUsernameInput.value || '').trim();
  const password = String(loginPasswordInput.value || '');

  if (!username || !password) {
    loginErrorMessage.value = 'Username and password are required.';
    return;
  }

  loginSubmitting.value = true;
  loginErrorMessage.value = '';

  try {
    const response = await fetch(`${apiBaseUrl}/api/auth/login`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ username, password })
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Invalid username or password.');
    }

    const data = await response.json();
    const token = String(data?.token || '').trim();
    if (!token) {
      throw new Error('Login succeeded but token was missing.');
    }

    authToken.value = token;
    isLoggedIn.value = true;
    sessionStorage.setItem(loginStorageKey, token);
    closeLoginDialog();
  } catch (error) {
    loginErrorMessage.value = error.message || 'Login failed.';
  } finally {
    loginSubmitting.value = false;
  }
}

function logout() {
  authToken.value = '';
  isLoggedIn.value = false;
  sessionStorage.removeItem(loginStorageKey);
  if (currentView.value === 'json-loader') {
    currentView.value = 'leader-boards';
  }
}

function buildAuthHeaders(extraHeaders = {}) {
  return {
    ...extraHeaders,
    Authorization: `Bearer ${authToken.value}`
  };
}

async function fetchWithAuth(url, options = {}) {
  if (!authToken.value) {
    logout();
    openLoginDialog();
    throw new Error('Login required.');
  }

  const headers = buildAuthHeaders(options.headers || {});
  const response = await fetch(url, {
    ...options,
    headers
  });

  if (response.status === 401) {
    logout();
    openLoginDialog();
  }

  return response;
}

function formatResultCell(row, column) {
  if (column === 'team_name' || column === 'team_member') {
    return row[column] || ' ';
  }

  const numericValue = Number(row[column] ?? 0);
  if (!Number.isFinite(numericValue) || numericValue === 0) {
    return ' ';
  }

  return numericValue;
}

function shouldHighlightMemberName(memberName) {
  const words = String(memberName || '')
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (words.length === 0) {
    return false;
  }

  if (words.length === 1 || words.length > 2) {
    return true;
  }

  const startsWithCapital = (value) => /^[A-Z]/.test(String(value || '').trim());
  const firstName = words[0];
  const lastName = words[words.length - 1];

  return !startsWithCapital(firstName) || !startsWithCapital(lastName);
}

async function fetchResultsEvents() {
  if (resultsEventsLoading.value) {
    return;
  }

  resultsEventsLoading.value = true;
  resultsEventsErrorMessage.value = '';

  try {
    const response = await fetch(`${apiBaseUrl}/api/events`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load events');
    }

    const data = await response.json();
    resultsEvents.value = Array.isArray(data) ? data : [];
  } catch (error) {
    resultsEventsErrorMessage.value = error.message || 'Failed to load events';
  } finally {
    resultsEventsLoading.value = false;
  }
}

async function loadSelectedEventResults() {
  const eventId = Number(selectedResultsEventId.value);
  eventResultsErrorMessage.value = '';
  eventResultsRows.value = [];
  selectedResultsEvent.value = null;

  if (!Number.isInteger(eventId) || eventId <= 0) {
    return;
  }

  eventResultsLoading.value = true;

  try {
    const response = await fetch(`${apiBaseUrl}/api/events/${eventId}/results`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load event results');
    }

    const data = await response.json();
    selectedResultsEvent.value = data?.event || null;
    const rows = Array.isArray(data?.rows) ? data.rows : [];

    eventResultsRows.value = rows.map((item) => ({
      id: Number(item?.id ?? 0),
      team_name: String(item?.team_name || ''),
      team_member: String(item?.team_member || ''),
      raw: {
        final_score: Number(item?.final_score_raw ?? 0),
        MJ: Number(item?.mj_raw ?? 0),
        WJ: Number(item?.wj_raw ?? 0),
        XJ: Number(item?.xj_raw ?? 0),
        MO: Number(item?.mo_raw ?? 0),
        WO: Number(item?.wo_raw ?? 0),
        XO: Number(item?.xo_raw ?? 0),
        MV: Number(item?.mv_raw ?? 0),
        WV: Number(item?.wv_raw ?? 0),
        XV: Number(item?.xv_raw ?? 0),
        MSV: Number(item?.msv_raw ?? 0),
        WSV: Number(item?.wsv_raw ?? 0),
        XSV: Number(item?.xsv_raw ?? 0),
        MUV: Number(item?.muv_raw ?? 0),
        WUV: Number(item?.wuv_raw ?? 0),
        XUV: Number(item?.xuv_raw ?? 0)
      },
      scaled: {
        final_score: Number(item?.final_score_scaled ?? 0),
        MJ: Number(item?.mj_scaled ?? 0),
        WJ: Number(item?.wj_scaled ?? 0),
        XJ: Number(item?.xj_scaled ?? 0),
        MO: Number(item?.mo_scaled ?? 0),
        WO: Number(item?.wo_scaled ?? 0),
        XO: Number(item?.xo_scaled ?? 0),
        MV: Number(item?.mv_scaled ?? 0),
        WV: Number(item?.wv_scaled ?? 0),
        XV: Number(item?.xv_scaled ?? 0),
        MSV: Number(item?.msv_scaled ?? 0),
        WSV: Number(item?.wsv_scaled ?? 0),
        XSV: Number(item?.xsv_scaled ?? 0),
        MUV: Number(item?.muv_scaled ?? 0),
        WUV: Number(item?.wuv_scaled ?? 0),
        XUV: Number(item?.xuv_scaled ?? 0)
      }
    }));
  } catch (error) {
    eventResultsErrorMessage.value = error.message || 'Failed to load event results';
  } finally {
    eventResultsLoading.value = false;
  }
}

function openEditResultDialog(row) {
  if (!isLoggedIn.value) {
    openLoginDialog();
    return;
  }

  const resultId = Number(row?.id);
  if (!Number.isInteger(resultId) || resultId <= 0) {
    return;
  }

  editResultId.value = resultId;
  editResultTeamName.value = String(row?.team_name || '');
  editResultTeamMember.value = String(row?.team_member || '');
  editResultErrorMessage.value = '';
  showEditResultDialog.value = true;
}

function closeEditResultDialog() {
  showEditResultDialog.value = false;
  editResultId.value = null;
  editResultErrorMessage.value = '';
}

async function saveEditedResultRow() {
  editResultErrorMessage.value = '';

  const eventId = Number(selectedResultsEventId.value);
  const resultId = Number(editResultId.value);

  if (!Number.isInteger(eventId) || eventId <= 0) {
    editResultErrorMessage.value = 'Select an event first.';
    return;
  }

  if (!Number.isInteger(resultId) || resultId <= 0) {
    editResultErrorMessage.value = 'Invalid result row selected.';
    return;
  }

  const payload = {
    team_name: String(editResultTeamName.value || '').trim(),
    team_member: String(editResultTeamMember.value || '').trim()
  };

  if (!payload.team_member) {
    editResultErrorMessage.value = 'Member is required.';
    return;
  }

  editResultLoading.value = true;

  try {
    const response = await fetchWithAuth(`${apiBaseUrl}/api/events/${eventId}/results/${resultId}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to update result row');
    }

    await loadSelectedEventResults();
    closeEditResultDialog();
  } catch (error) {
    editResultErrorMessage.value = error.message || 'Failed to update result row';
  } finally {
    editResultLoading.value = false;
  }
}

async function deleteResultRow(row) {
  if (!isLoggedIn.value) {
    openLoginDialog();
    return;
  }

  const eventId = Number(selectedResultsEventId.value);
  const resultId = Number(row?.id);

  if (!Number.isInteger(eventId) || eventId <= 0 || !Number.isInteger(resultId) || resultId <= 0) {
    return;
  }

  const confirmed = window.confirm('Delete this result row?');
  if (!confirmed) {
    return;
  }

  eventResultsErrorMessage.value = '';

  try {
    const response = await fetchWithAuth(`${apiBaseUrl}/api/events/${eventId}/results/${resultId}`, {
      method: 'DELETE'
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to delete result row');
    }

    await loadSelectedEventResults();
  } catch (error) {
    eventResultsErrorMessage.value = error.message || 'Failed to delete result row';
  }
}

watch(selectedResultsEventId, () => {
  if (currentView.value === 'results') {
    loadSelectedEventResults();
  }
});

async function fetchLeaderBoards() {
  leaderBoardsLoading.value = true;
  leaderBoardsErrorMessage.value = '';

  try {
    const response = await fetch(`${apiBaseUrl}/api/leader-boards`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load leader boards');
    }

    const data = await response.json();
    leaderBoards.value = Array.isArray(data) ? data : [];
  } catch (error) {
    leaderBoardsErrorMessage.value = error.message || 'Failed to load leader boards';
  } finally {
    leaderBoardsLoading.value = false;
  }
}

async function createLeaderBoardScoreView(leaderBoard) {
  if (!leaderBoard?.id) {
    return;
  }

  activeLeaderBoard.value = {
    id: leaderBoard.id,
    name: leaderBoard.name,
    year: leaderBoard.year,
    eventCount: leaderBoard.eventCount
  };
  leaderBoardScoresRows.value = [];
  leaderBoardScoresErrorMessage.value = '';
  leaderBoardScoresShowRaw.value = false;
  leaderBoardScoresShowRank.value = false;
  leaderBoardScoreSortColumn.value = 'final_score';
  leaderBoardScoreSortDirection.value = 'desc';
  leaderBoardScoresLoading.value = true;

  try {
    const response = await fetch(`${apiBaseUrl}/api/leader-boards/${leaderBoard.id}/scoreboard`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to create leader board scores');
    }

    const data = await response.json();
    const rows = Array.isArray(data?.rows) ? data.rows : [];

    leaderBoardScoresRows.value = rows.map((item) => {
      const rawValues = {
        event_count: Number(item?.event_count ?? 0),
        final_score: Number(item?.final_score_raw ?? 0),
        MJ: Number(item?.mj_raw ?? 0),
        WJ: Number(item?.wj_raw ?? 0),
        XJ: Number(item?.xj_raw ?? 0),
        MO: Number(item?.mo_raw ?? 0),
        WO: Number(item?.wo_raw ?? 0),
        XO: Number(item?.xo_raw ?? 0),
        MV: Number(item?.mv_raw ?? 0),
        WV: Number(item?.wv_raw ?? 0),
        XV: Number(item?.xv_raw ?? 0),
        MSV: Number(item?.msv_raw ?? 0),
        WSV: Number(item?.wsv_raw ?? 0),
        XSV: Number(item?.xsv_raw ?? 0),
        MUV: Number(item?.muv_raw ?? 0),
        WUV: Number(item?.wuv_raw ?? 0),
        XUV: Number(item?.xuv_raw ?? 0)
      };

      const scaledValues = {
        event_count: Number(item?.event_count ?? 0),
        final_score: Number(item?.final_score_scaled ?? 0),
        MJ: Number(item?.mj_scaled ?? 0),
        WJ: Number(item?.wj_scaled ?? 0),
        XJ: Number(item?.xj_scaled ?? 0),
        MO: Number(item?.mo_scaled ?? 0),
        WO: Number(item?.wo_scaled ?? 0),
        XO: Number(item?.xo_scaled ?? 0),
        MV: Number(item?.mv_scaled ?? 0),
        WV: Number(item?.wv_scaled ?? 0),
        XV: Number(item?.xv_scaled ?? 0),
        MSV: Number(item?.msv_scaled ?? 0),
        WSV: Number(item?.wsv_scaled ?? 0),
        XSV: Number(item?.xsv_scaled ?? 0),
        MUV: Number(item?.muv_scaled ?? 0),
        WUV: Number(item?.wuv_scaled ?? 0),
        XUV: Number(item?.xuv_scaled ?? 0)
      };

      return {
        team_name: String(item?.team_name || ''),
        team_member: String(item?.team_member || ''),
        raw: rawValues,
        scaled: scaledValues
      };
    });
  } catch (error) {
    leaderBoardScoresErrorMessage.value = error.message || 'Failed to create leader board scores';
  } finally {
    leaderBoardScoresLoading.value = false;
  }
}

function openCreateLeaderBoardDialog() {
  createLeaderBoardErrorMessage.value = '';
  createLeaderBoardSuccessMessage.value = '';
  newLeaderBoardName.value = '';
  newLeaderBoardYear.value = '';
  leaderBoardYearResults.value = [];
  leaderBoardYearResultsErrorMessage.value = '';
  selectedLeaderBoardResultIds.value = [];
  showCreateLeaderBoardDialog.value = true;
}

function closeCreateLeaderBoardDialog() {
  showCreateLeaderBoardDialog.value = false;
  createLeaderBoardErrorMessage.value = '';
  leaderBoardYearResultsErrorMessage.value = '';
}

async function openEditLeaderBoardDialog(leaderBoard) {
  if (!isLoggedIn.value) {
    openLoginDialog();
    return;
  }

  const leaderBoardId = Number(leaderBoard?.id);
  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    return;
  }

  createLeaderBoardSuccessMessage.value = '';
  editLeaderBoardErrorMessage.value = '';
  editLeaderBoardYearResultsErrorMessage.value = '';
  editLeaderBoardId.value = leaderBoardId;
  editLeaderBoardName.value = String(leaderBoard?.name || '').trim();
  editLeaderBoardYear.value = String(leaderBoard?.year || '').trim();
  editLeaderBoardYearResults.value = [];
  selectedEditLeaderBoardResultIds.value = [];
  showEditLeaderBoardDialog.value = true;
  editLeaderBoardLoadingDetails.value = true;

  try {
    const response = await fetch(`${apiBaseUrl}/api/leader-boards/details/${leaderBoardId}`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load leader board details');
    }

    const data = await response.json();
    const loadedLeaderBoard = data?.leaderBoard || {};
    editLeaderBoardName.value = String(loadedLeaderBoard?.name || '').trim();
    editLeaderBoardYear.value = String(loadedLeaderBoard?.year || '').trim();

    selectedEditLeaderBoardResultIds.value = Array.isArray(data?.eventIds)
      ? [...new Set(data.eventIds.map((value) => Number(value)).filter((value) => Number.isInteger(value) && value > 0))]
      : [];

    await fetchEditLeaderBoardYearResults(true);
  } catch (error) {
    editLeaderBoardErrorMessage.value = error.message || 'Failed to load leader board details';
  } finally {
    editLeaderBoardLoadingDetails.value = false;
  }
}

function closeEditLeaderBoardDialog() {
  showEditLeaderBoardDialog.value = false;
  editLeaderBoardId.value = null;
  editLeaderBoardErrorMessage.value = '';
  editLeaderBoardYearResultsErrorMessage.value = '';
}

async function fetchEditLeaderBoardYearResults(preserveSelection = false) {
  const year = Number(editLeaderBoardYear.value);
  editLeaderBoardYearResultsErrorMessage.value = '';
  editLeaderBoardYearResults.value = [];

  if (!preserveSelection) {
    selectedEditLeaderBoardResultIds.value = [];
  }

  if (!Number.isInteger(year) || year <= 0) {
    return;
  }

  editLeaderBoardYearResultsLoading.value = true;

  try {
    const query = new URLSearchParams({ year: String(year) });
    const response = await fetch(`${apiBaseUrl}/api/leader-boards/year-results?${query.toString()}`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load results for selected year');
    }

    const data = await response.json();
    editLeaderBoardYearResults.value = Array.isArray(data) ? data : [];

    const validIds = new Set(editLeaderBoardYearResults.value.map((result) => Number(result.id)).filter((value) => Number.isInteger(value) && value > 0));
    selectedEditLeaderBoardResultIds.value = selectedEditLeaderBoardResultIds.value.filter((id) => validIds.has(id));
  } catch (error) {
    editLeaderBoardYearResultsErrorMessage.value = error.message || 'Failed to load results for selected year';
  } finally {
    editLeaderBoardYearResultsLoading.value = false;
  }
}

function toggleEditLeaderBoardResultSelection(eventId) {
  const numericId = Number(eventId);
  if (!Number.isInteger(numericId) || numericId <= 0) {
    return;
  }

  if (selectedEditLeaderBoardResultIds.value.includes(numericId)) {
    selectedEditLeaderBoardResultIds.value = selectedEditLeaderBoardResultIds.value.filter((id) => id !== numericId);
    return;
  }

  selectedEditLeaderBoardResultIds.value = [...selectedEditLeaderBoardResultIds.value, numericId];
}

async function updateLeaderBoard() {
  editLeaderBoardErrorMessage.value = '';
  createLeaderBoardSuccessMessage.value = '';

  const leaderBoardId = Number(editLeaderBoardId.value);
  const payload = {
    name: String(editLeaderBoardName.value || '').trim(),
    year: Number(editLeaderBoardYear.value),
    eventIds: selectedEditLeaderBoardResultIds.value
  };

  if (!Number.isInteger(leaderBoardId) || leaderBoardId <= 0) {
    editLeaderBoardErrorMessage.value = 'Invalid leader board selected.';
    return;
  }

  if (!payload.name || !Number.isInteger(payload.year) || payload.year <= 0) {
    editLeaderBoardErrorMessage.value = 'Name and Year (positive integer) are required.';
    return;
  }

  if (!Array.isArray(payload.eventIds) || payload.eventIds.length === 0) {
    editLeaderBoardErrorMessage.value = 'Select at least one result to include in the leader board.';
    return;
  }

  editLeaderBoardLoading.value = true;

  try {
    const response = await fetchWithAuth(`${apiBaseUrl}/api/leader-boards/${leaderBoardId}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to update leader board');
    }

    const data = await response.json();
    createLeaderBoardSuccessMessage.value = data.message || 'Leader board updated successfully.';
    await fetchLeaderBoards();

    if (activeLeaderBoard.value?.id === leaderBoardId) {
      activeLeaderBoard.value = {
        ...activeLeaderBoard.value,
        name: payload.name,
        year: payload.year,
        eventCount: payload.eventIds.length
      };
      await createLeaderBoardScoreView(activeLeaderBoard.value);
    }

    closeEditLeaderBoardDialog();
  } catch (error) {
    editLeaderBoardErrorMessage.value = error.message || 'Failed to update leader board';
  } finally {
    editLeaderBoardLoading.value = false;
  }
}

async function fetchLeaderBoardYearResults() {
  const year = Number(newLeaderBoardYear.value);
  leaderBoardYearResultsErrorMessage.value = '';
  leaderBoardYearResults.value = [];
  selectedLeaderBoardResultIds.value = [];

  if (!Number.isInteger(year) || year <= 0) {
    return;
  }

  leaderBoardYearResultsLoading.value = true;

  try {
    const query = new URLSearchParams({ year: String(year) });
    const response = await fetch(`${apiBaseUrl}/api/leader-boards/year-results?${query.toString()}`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load results for selected year');
    }

    const data = await response.json();
    leaderBoardYearResults.value = Array.isArray(data) ? data : [];
  } catch (error) {
    leaderBoardYearResultsErrorMessage.value = error.message || 'Failed to load results for selected year';
  } finally {
    leaderBoardYearResultsLoading.value = false;
  }
}

function toggleLeaderBoardResultSelection(eventId) {
  const numericId = Number(eventId);
  if (!Number.isInteger(numericId) || numericId <= 0) {
    return;
  }

  if (selectedLeaderBoardResultIds.value.includes(numericId)) {
    selectedLeaderBoardResultIds.value = selectedLeaderBoardResultIds.value.filter((id) => id !== numericId);
    return;
  }

  selectedLeaderBoardResultIds.value = [...selectedLeaderBoardResultIds.value, numericId];
}

async function createLeaderBoard() {
  createLeaderBoardErrorMessage.value = '';
  createLeaderBoardSuccessMessage.value = '';

  const payload = {
    name: String(newLeaderBoardName.value || '').trim(),
    year: Number(newLeaderBoardYear.value),
    eventIds: selectedLeaderBoardResultIds.value
  };

  if (!payload.name || !Number.isInteger(payload.year) || payload.year <= 0) {
    createLeaderBoardErrorMessage.value = 'Name and Year (positive integer) are required.';
    return;
  }

  if (!Array.isArray(payload.eventIds) || payload.eventIds.length === 0) {
    createLeaderBoardErrorMessage.value = 'Select at least one result to include in the leader board.';
    return;
  }

  createLeaderBoardLoading.value = true;

  try {
    const response = await fetch(`${apiBaseUrl}/api/leader-boards`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to create leader board');
    }

    const data = await response.json();
    createLeaderBoardSuccessMessage.value = data.message || 'Leader board created successfully.';
    await fetchLeaderBoards();
    closeCreateLeaderBoardDialog();
  } catch (error) {
    createLeaderBoardErrorMessage.value = error.message || 'Failed to create leader board';
  } finally {
    createLeaderBoardLoading.value = false;
  }
}

async function fetchEventsIndex() {
  if (eventsIndexLoading.value) {
    return;
  }

  eventsIndexLoading.value = true;
  eventsIndexErrorMessage.value = '';

  try {
    const query = new URLSearchParams({
      url: 'https://rogaine-results.com/events.json'
    });

    const response = await fetch(`${apiBaseUrl}/api/json-loader?${query.toString()}`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load events index');
    }

    const data = await response.json();
    eventsIndex.value = Array.isArray(data) ? data : [];
  } catch (error) {
    eventsIndexErrorMessage.value = error.message || 'Failed to load events index';
  } finally {
    eventsIndexLoading.value = false;
  }
}

function normalizeTeamMemberName(value) {
  const collapsed = String(value || '').trim().replace(/\s+/g, ' ');
  if (!collapsed) {
    return '';
  }

  const lettersOnly = collapsed.replace(/[^a-zA-Z]/g, '');
  if (!lettersOnly) {
    return collapsed;
  }

  const isAllUpper = lettersOnly === lettersOnly.toUpperCase();
  const isAllLower = lettersOnly === lettersOnly.toLowerCase();

  if (!(isAllUpper || isAllLower)) {
    return collapsed;
  }

  const lower = collapsed.toLowerCase();
  return lower.replace(/(^|[^a-zA-Z])([a-z])/g, (match, prefix, letter) => `${prefix}${letter.toUpperCase()}`);
}

function hasNzCountryCode(value) {
  const text = String(value || '').trim();
  const match = text.match(/\(([^)]+)\)\s*$/);
  if (!match) {
    return false;
  }

  const code = String(match[1] || '').trim().toUpperCase();
  return code === 'NZ' || code === 'NZL';
}

function stripTrailingCountryCode(value) {
  return String(value || '').trim().replace(/\s*\(([^)]+)\)\s*$/g, '').trim();
}

function parseTeamNameAndMembers(rawName) {
  const fullName = String(rawName || '');
  const separatorIndex = fullName.indexOf(';');

  if (separatorIndex >= 0) {
    const teamName = normalizeTeamMemberName(fullName.slice(0, separatorIndex));
    const membersText = fullName.slice(separatorIndex + 1);
    const members = membersText
      .split(',')
      .map((member) => normalizeTeamMemberName(member))
      .filter(Boolean);

    return {
      teamName,
      members
    };
  }

  const colonIndex = fullName.indexOf(':');
  if (colonIndex >= 0) {
    const teamName = normalizeTeamMemberName(fullName.slice(0, colonIndex));
    const membersText = fullName.slice(colonIndex + 1);
    const members = membersText
      .split(',')
      .map((member) => normalizeTeamMemberName(member.replace(/[.]+$/g, '')))
      .filter(Boolean);

    return {
      teamName,
      members
    };
  }

  const parenthesizedMemberListPattern = /^\s*[^,;:]+?\([^)]*\)\s*(,\s*[^,;:]+?\([^)]*\)\s*)+$/;
  if (parenthesizedMemberListPattern.test(fullName)) {
    const members = fullName
      .split(',')
      .map((member) => normalizeTeamMemberName(member))
      .filter(Boolean);

    return {
      teamName: members[0] || '',
      members
    };
  }

  const openParenIndex = fullName.indexOf('(');
  if (openParenIndex >= 0) {
    const teamName = normalizeTeamMemberName(fullName.slice(0, openParenIndex));
    const membersText = fullName.slice(openParenIndex + 1);
    const members = membersText
      .split(',')
      .map((member) => normalizeTeamMemberName(member.replace(/[.]+$/g, '')))
      .filter(Boolean);

    return {
      teamName,
      members
    };
  }

  const teamName = normalizeTeamMemberName(fullName);
  const members = [normalizeTeamMemberName(fullName)].filter(Boolean);

  return {
    teamName,
    members
  };
}

function normalizeRawTeamCategory(value) {
  let normalized = String(value || '').trim().toUpperCase();
  normalized = normalized.replace(/[\s:;]*\d+$/g, '').trim();
  normalized = normalized.replace(/[:;]+$/g, '').trim();
  return normalized;
}

function extractNormalizedTeamCategories(value) {
  const rawValue = String(value || '').trim();
  if (!rawValue) {
    return [];
  }

  const groupedPattern = /[^,;]+?\d+(?=\s+[^,;]+?\d+|$|[,;])/g;
  const groupedMatches = rawValue.match(groupedPattern);

  const rawCategories = groupedMatches && groupedMatches.length > 0
    ? groupedMatches
    : rawValue.split(/[;,]+/).map((token) => token.trim()).filter(Boolean);

  return [...new Set(
    rawCategories
      .map((token) => normalizeRawTeamCategory(token))
      .filter(Boolean)
  )];
}

function transformLoadedJson() {
  transformErrorMessage.value = '';
  transformedRows.value = [];
  transformedDisplayMode.value = 'raw';

  if (!jsonLoadData.value || typeof jsonLoadData.value !== 'object') {
    transformErrorMessage.value = 'Load results data first.';
    return;
  }

  const categories = fixedCategoryColumns;

  const teamsData = Array.isArray(jsonLoadData.value.teams) ? jsonLoadData.value.teams : [];

  if (teamsData.length === 0) {
    transformErrorMessage.value = 'No teams found in loaded results.';
    return;
  }

  const rows = [];
  const hasAnyNzTaggedMember = teamsData.some((team) => {
    const { members } = parseTeamNameAndMembers(team?.name);
    return members.some((member) => hasNzCountryCode(member));
  });

  const categoryMapping = new Map(
    fixedCategoryColumns.map((category) => [normalizeRawTeamCategory(category), category])
  );

  for (const row of categoryMappingRows.value) {
    const rawCategory = normalizeRawTeamCategory(row?.rawCategory);
    const mappedCategory = normalizeRawTeamCategory(row?.mappedCategory);

    if (rawCategory && mappedCategory) {
      categoryMapping.set(rawCategory, mappedCategory);
    }
  }

  for (const team of teamsData) {
    const { teamName, members } = parseTeamNameAndMembers(team?.name);
    const filteredMembers = hasAnyNzTaggedMember
      ? members.filter((member) => hasNzCountryCode(member))
      : members;
    if (filteredMembers.length === 0) {
      continue;
    }

    const finalScore = team?.final_score ?? null;
    const rawTeamCategories = extractNormalizedTeamCategories(team?.category);
    const mappedTeamCategories = new Set(
      rawTeamCategories
        .map((rawCategory) => categoryMapping.get(rawCategory) || '')
        .filter(Boolean)
    );

    for (const member of filteredMembers) {
      const row = {
        team_name: teamName,
        team_member: stripTrailingCountryCode(member),
        final_score: finalScore
      };

      for (const category of categories) {
        row[category] = mappedTeamCategories.has(category) ? finalScore : '';
      }

      rows.push(row);
    }
  }

  transformedColumns.value = ['team_name', 'team_member', 'final_score', ...fixedCategoryColumns];
  transformedRows.value = rows;
}

function openCategoryMappingDialog() {
  transformErrorMessage.value = '';
  categoryMappingErrorMessage.value = '';

  if (!jsonLoadData.value || typeof jsonLoadData.value !== 'object') {
    transformErrorMessage.value = 'Load results data first.';
    return;
  }

  const rawGrades = Array.isArray(jsonLoadData.value.event_grades)
    ? jsonLoadData.value.event_grades.map((grade) => String(grade).trim()).filter(Boolean)
    : [];

  if (rawGrades.length === 0) {
    transformErrorMessage.value = 'No event_grades found in loaded results.';
    return;
  }

  categoryMappingRows.value = rawGrades.map((grade) => ({
    rawCategory: grade,
    mappedCategory: fixedCategoryColumns.includes(normalizeRawTeamCategory(grade))
      ? normalizeRawTeamCategory(grade)
      : ''
  }));

  showCategoryMappingDialog.value = true;
}

function closeCategoryMappingDialog() {
  categoryMappingErrorMessage.value = '';
  showCategoryMappingDialog.value = false;
}

function applyCategoryMappingAndTransform() {
  categoryMappingErrorMessage.value = '';
  showCategoryMappingDialog.value = false;
  transformLoadedJson();
}

async function saveSelectedEvent(overwrite = false) {
  saveEventErrorMessage.value = '';
  saveEventSuccessMessage.value = '';

  if (!jsonLoadData.value || !selectedEventDetails.value) {
    saveEventErrorMessage.value = 'Load results and select an event before saving.';
    return;
  }

  const payload = {
    year: Number(selectedEventYear.value),
    series: String(selectedEventSeries.value || '').trim(),
    name: String(selectedEventDetails.value.title || '').trim(),
    date: String(jsonLoadData.value.start_date || '').trim(),
    organiser: String(jsonLoadData.value.organiser || '').trim(),
    duration: Number(jsonLoadData.value.event_duration),
    overwrite
  };

  if (!payload.year || !payload.series || !payload.name || !payload.date || !payload.organiser || Number.isNaN(payload.duration)) {
    saveEventErrorMessage.value = 'Missing required event details to save.';
    return;
  }

  saveEventLoading.value = true;

  try {
    const response = await fetchWithAuth(`${apiBaseUrl}/api/events/save-result`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (response.status === 409 && !overwrite) {
      const shouldOverwrite = window.confirm('Event already exists. Overwrite existing event details?');
      if (shouldOverwrite) {
        saveEventLoading.value = false;
        await saveSelectedEvent(true);
      }
      return;
    }

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to save event details');
    }

    const data = await response.json();
    saveEventSuccessMessage.value = data.message || 'Event saved successfully.';
    savedEventId.value = Number(data?.event?.id) || null;
  } catch (error) {
    saveEventErrorMessage.value = error.message || 'Failed to save event details';
  } finally {
    saveEventLoading.value = false;
  }
}

async function saveTransformedResults() {
  saveTransformedErrorMessage.value = '';
  saveTransformedSuccessMessage.value = '';

  if (transformedRows.value.length === 0) {
    saveTransformedErrorMessage.value = 'Run Transform before saving results.';
    return;
  }

  if (!savedEventId.value) {
    saveTransformedErrorMessage.value = 'Save Event first so transformed data can be linked.';
    return;
  }

  const rowsPayload = transformedRows.value.map((row, index) => {
    const scaledRow = scaledRows.value[index] || {};

    const raw = {
      final_score: row.final_score ?? null
    };

    const scaled = {
      final_score: scaledRow.final_score ?? null
    };

    for (const category of fixedCategoryColumns) {
      raw[category] = row[category] ?? null;
      scaled[category] = scaledRow[category] ?? null;
    }

    return {
      team_name: row.team_name,
      team_member: row.team_member,
      raw,
      scaled
    };
  });

  saveTransformedLoading.value = true;

  try {
    const response = await fetchWithAuth(`${apiBaseUrl}/api/events/${savedEventId.value}/transformed-results`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ rows: rowsPayload })
    });

    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to save transformed results');
    }

    const data = await response.json();
    saveTransformedSuccessMessage.value = data.message || 'Transformed results saved successfully.';
  } catch (error) {
    saveTransformedErrorMessage.value = error.message || 'Failed to save transformed results';
  } finally {
    saveTransformedLoading.value = false;
  }
}

async function loadSelectedEventJson() {
  const url = selectedEventResultsUrl.value;
  if (!url) {
    jsonLoadErrorMessage.value = 'Select year and event before loading.';
    return;
  }

  jsonLoadLoading.value = true;
  jsonLoadErrorMessage.value = '';

  try {
    const query = new URLSearchParams({ url });
    const response = await fetch(`${apiBaseUrl}/api/json-loader?${query.toString()}`);
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.message || 'Failed to load results from URL');
    }

    const data = await response.json();
    jsonLoadData.value = data;
    transformErrorMessage.value = '';
    transformedRows.value = [];
    transformedColumns.value = [];
    saveEventErrorMessage.value = '';
    saveEventSuccessMessage.value = '';
    saveTransformedErrorMessage.value = '';
    saveTransformedSuccessMessage.value = '';
    savedEventId.value = null;
  } catch (error) {
    jsonLoadErrorMessage.value = error.message || 'Failed to load results';
    jsonLoadData.value = null;
    transformErrorMessage.value = '';
    transformedRows.value = [];
    transformedColumns.value = [];
    saveEventErrorMessage.value = '';
    saveEventSuccessMessage.value = '';
    saveTransformedErrorMessage.value = '';
    saveTransformedSuccessMessage.value = '';
    savedEventId.value = null;
  } finally {
    jsonLoadLoading.value = false;
  }
}

onMounted(() => {
  const storedToken = String(sessionStorage.getItem(loginStorageKey) || '').trim();
  if (storedToken) {
    authToken.value = storedToken;
    isLoggedIn.value = true;

    fetch(`${apiBaseUrl}/api/auth/validate`, {
      headers: buildAuthHeaders()
    })
      .then((response) => {
        if (!response.ok) {
          logout();
        }
      })
      .catch(() => {
        logout();
      });
  }

  fetchEventsIndex();
  fetchLeaderBoards();
});
</script>

<template>
  <main class="mx-auto my-8 max-w-[1240px] px-4 font-sans text-slate-800 lg:px-6">
    <header class="page-header rounded-xl border border-slate-200 bg-white px-5 py-4 shadow-sm">
      <h1 class="text-3xl font-bold tracking-tight text-slate-900">Rogainizer</h1>

      <div class="mt-3 flex flex-nowrap items-center gap-3">
        <div class="view-switcher">
          <button
            type="button"
            class="tab-button rounded-md border border-transparent bg-transparent px-3 py-2 text-sm font-medium text-slate-700 shadow-none transition"
            :class="{ active: currentView === 'leader-boards', 'border-indigo-200 bg-white font-semibold text-indigo-700 shadow-sm': currentView === 'leader-boards' }"
            @click="switchView('leader-boards')"
          >Leader Boards</button>
          <button
            type="button"
            class="tab-button rounded-md border border-transparent bg-transparent px-3 py-2 text-sm font-medium text-slate-700 shadow-none transition"
            :class="{ active: currentView === 'results', 'border-indigo-200 bg-white font-semibold text-indigo-700 shadow-sm': currentView === 'results' }"
            @click="switchView('results')"
          >Results</button>
          <button
            v-if="isLoggedIn"
            type="button"
            class="tab-button rounded-md border border-transparent bg-transparent px-3 py-2 text-sm font-medium text-slate-700 shadow-none transition"
            :class="{ active: currentView === 'json-loader', 'border-indigo-200 bg-white font-semibold text-indigo-700 shadow-sm': currentView === 'json-loader' }"
            @click="switchView('json-loader')"
          >Results Loader</button>
        </div>

        <div class="ml-auto flex items-center gap-2">
          <span v-if="isLoggedIn" class="rounded-full bg-green-100 px-2.5 py-1 text-xs font-semibold text-green-700">Logged in</span>
          <button v-if="!isLoggedIn" type="button" class="rounded-md border border-indigo-600 bg-indigo-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-indigo-700" @click="openLoginDialog">Login</button>
          <button v-else type="button" class="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 hover:bg-slate-100" @click="logout">Logout</button>
        </div>
      </div>
    </header>

    <section v-if="currentView === 'json-loader' && isLoggedIn" class="json-loader-section mt-4 rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm">
        <h2 class="mb-2 text-xl font-semibold text-slate-900">Load Results</h2>
        <p class="json-loader-subtitle mt-0 text-sm text-slate-600">Select year, event series, and event, then click Load to retrieve results.</p>
        <div class="json-loader-controls">
          <label>
            Year
            <input v-model="selectedEventYear" type="text" inputmode="numeric" placeholder="2026" />
          </label>
          <label>
            Event Series
            <select v-model="selectedEventSeries" :disabled="filteredEventSeries.length === 0">
              <option value="" disabled>Select event series</option>
              <option v-for="series in filteredEventSeries" :key="`series-${series}`" :value="series">
                {{ series }}
              </option>
            </select>
          </label>
          <label>
            Event
            <select v-model="selectedEventTitle" :disabled="filteredEvents.length === 0">
              <option value="" disabled>Select event</option>
              <option v-for="eventItem in filteredEvents" :key="`event-${eventItem.key}`" :value="eventItem.key">
                {{ eventItem.title }}
              </option>
            </select>
          </label>
        </div>
        <p v-if="eventsIndexLoading">Loading events index...</p>
        <p v-if="eventsIndexErrorMessage" class="error">{{ eventsIndexErrorMessage }}</p>
        <div class="action-row mb-2 mt-3 flex flex-wrap items-center gap-2">
          <button type="button" class="rounded-md border border-indigo-600 bg-indigo-600 px-3 py-2 text-sm font-medium text-white shadow-sm transition hover:border-indigo-700 hover:bg-indigo-700 disabled:cursor-not-allowed disabled:border-slate-300 disabled:bg-slate-200 disabled:text-slate-500" @click="loadSelectedEventJson" :disabled="jsonLoadLoading || !selectedEventResultsUrl">
            {{ jsonLoadLoading ? 'Loading...' : 'Load' }}
          </button>
          <button type="button" class="rounded-md border border-indigo-600 bg-indigo-600 px-3 py-2 text-sm font-medium text-white shadow-sm transition hover:border-indigo-700 hover:bg-indigo-700 disabled:cursor-not-allowed disabled:border-slate-300 disabled:bg-slate-200 disabled:text-slate-500" @click="saveSelectedEvent()" :disabled="saveEventLoading || jsonLoadData === null">
            {{ saveEventLoading ? 'Saving...' : 'Save Event' }}
          </button>
          <button type="button" class="rounded-md border border-indigo-600 bg-indigo-600 px-3 py-2 text-sm font-medium text-white shadow-sm transition hover:border-indigo-700 hover:bg-indigo-700 disabled:cursor-not-allowed disabled:border-slate-300 disabled:bg-slate-200 disabled:text-slate-500" @click="openCategoryMappingDialog" :disabled="jsonLoadLoading || jsonLoadData === null">
            Transform
          </button>
        </div>
        <p v-if="selectedEventResultsUrl" class="json-loader-url">{{ selectedEventResultsUrl }}</p>
        <p v-if="jsonLoadErrorMessage" class="error">{{ jsonLoadErrorMessage }}</p>
        <p v-if="saveEventErrorMessage" class="error">{{ saveEventErrorMessage }}</p>
        <div v-if="saveEventSuccessMessage" class="success success-banner" role="status">
          <span>{{ saveEventSuccessMessage }}</span>
          <button
            type="button"
            class="plain-button dismiss-button"
            @click="saveEventSuccessMessage = ''"
            aria-label="Dismiss success message"
          >&times;</button>
        </div>
        <p v-if="transformErrorMessage" class="error">{{ transformErrorMessage }}</p>

        <div v-if="jsonLoadData !== null" class="json-panels">
          <div class="json-output-panel">
            <h3>Raw Results</h3>
            <JsonTreeNode :value="jsonLoadData" label="root" />
          </div>

          <div class="json-output-panel transformed-output-panel">
            <h3>Transformed Data</h3>
            <div v-if="transformedRows.length > 0" class="transformed-mode-switch">
              <label>
                <input v-model="transformedDisplayMode" type="radio" value="raw" />
                Raw
              </label>
              <label>
                <input v-model="transformedDisplayMode" type="radio" value="scaled" />
                Scaled
              </label>
              <button type="button" @click="saveTransformedResults" :disabled="saveTransformedLoading || transformedRows.length === 0">
                {{ saveTransformedLoading ? 'Saving...' : 'Save Results' }}
              </button>
            </div>
            <p v-if="saveTransformedErrorMessage" class="error">{{ saveTransformedErrorMessage }}</p>
            <div v-if="saveTransformedSuccessMessage" class="success success-banner" role="status">
              <span>{{ saveTransformedSuccessMessage }}</span>
              <button
                type="button"
                class="plain-button dismiss-button"
                @click="saveTransformedSuccessMessage = ''"
                aria-label="Dismiss success message"
              >&times;</button>
            </div>
            <table v-if="transformedRows.length > 0" class="events-table transformed-table">
              <thead>
                <tr>
                  <th v-for="column in transformedColumns" :key="`transform-header-${column}`">{{ transformedColumnLabel(column) }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(row, rowIndex) in displayedTransformedRows" :key="`transform-row-${rowIndex}`">
                  <td
                    v-for="column in transformedColumns"
                    :key="`transform-cell-${rowIndex}-${column}`"
                    :class="{
                      'scaled-score-cell': transformedDisplayMode === 'scaled' && column !== 'team_name' && column !== 'team_member'
                    }"
                  >
                    {{ row[column] }}
                  </td>
                </tr>
              </tbody>
            </table>
            <p v-else class="empty-state">Run Transform to view transformed rows.</p>
          </div>
        </div>
    </section>

    <section v-else-if="currentView === 'json-loader'" class="json-loader-section mt-4 rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm">
      <h2 class="mb-2 text-xl font-semibold text-slate-900">Results Loader</h2>
      <p class="empty-state">Login is required to access Results Loader.</p>
      <div class="mt-3">
        <button type="button" class="rounded-md border border-indigo-600 bg-indigo-600 px-3 py-2 text-sm font-medium text-white hover:bg-indigo-700" @click="openLoginDialog">Login</button>
      </div>
    </section>

    <section v-else-if="currentView === 'results'" class="json-loader-section mt-4 rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm">
      <h2 class="mb-2 text-xl font-semibold text-slate-900">Results</h2>
      <div class="json-loader-controls">
        <label>
          Event
          <select v-model="selectedResultsEventId" :disabled="resultsEventsLoading || resultsEvents.length === 0">
            <option value="" disabled>Select event</option>
            <option v-for="eventItem in resultsEvents" :key="`saved-event-${eventItem.id}`" :value="String(eventItem.id)">
              {{ eventItem.year }} - {{ eventItem.series }} - {{ eventItem.name }}
            </option>
          </select>
        </label>
      </div>
      <p v-if="resultsEventsLoading">Loading events...</p>
      <p v-if="resultsEventsErrorMessage" class="error">{{ resultsEventsErrorMessage }}</p>
      <p v-if="selectedResultsEvent">{{ selectedResultsEvent.name }} ({{ selectedResultsEvent.date }})</p>

      <div v-if="eventResultsRows.length > 0" class="transformed-mode-switch">
        <label>
          <input v-model="eventResultsDisplayMode" type="radio" value="raw" />
          Raw
        </label>
        <label>
          <input v-model="eventResultsDisplayMode" type="radio" value="scaled" />
          Scaled
        </label>
        <label>
          <input v-model="showOnlyFlaggedResultMembers" type="checkbox" />
          Flagged only
        </label>
      </div>

      <p v-if="eventResultsLoading">Loading results...</p>
      <p v-if="eventResultsErrorMessage" class="error">{{ eventResultsErrorMessage }}</p>

      <table v-if="!eventResultsLoading && filteredEventResultsRows.length > 0" class="events-table transformed-table my-4 w-full border-collapse overflow-hidden rounded-lg bg-white">
        <thead>
          <tr>
            <th v-for="column in eventResultsColumns" :key="`event-results-header-${column}`">{{ transformedColumnLabel(column) }}</th>
            <th v-if="isLoggedIn">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(row, rowIndex) in filteredEventResultsRows" :key="`event-results-row-${row.id || rowIndex}`">
            <td
              v-for="column in eventResultsColumns"
              :key="`event-results-cell-${rowIndex}-${column}`"
              :class="{
                'scaled-score-cell': eventResultsDisplayMode === 'scaled' && column !== 'team_name' && column !== 'team_member',
                'result-member-warning': column === 'team_member' && shouldHighlightMemberName(row.team_member)
              }"
            >
              {{ formatResultCell(row, column) }}
            </td>
            <td v-if="isLoggedIn" class="action-cell whitespace-nowrap">
              <button type="button" class="action-button mr-2 rounded-md border border-indigo-600 bg-indigo-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-indigo-700" @click="openEditResultDialog(row)">Edit</button>
              <button type="button" class="action-button danger-button rounded-md border border-red-600 bg-red-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-red-700" @click="deleteResultRow(row)">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-else-if="!eventResultsLoading" class="empty-state">No saved results for this event.</p>
    </section>

    <div v-if="showEditResultDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Edit result row">
        <h3>Edit Result Row</h3>
        <div class="json-loader-controls">
          <label>
            Team
            <input v-model="editResultTeamName" type="text" placeholder="Team name" />
          </label>
          <label>
            Member
            <input v-model="editResultTeamMember" type="text" placeholder="Member name" />
          </label>
        </div>
        <p v-if="editResultErrorMessage" class="error">{{ editResultErrorMessage }}</p>
        <div class="mapping-dialog-actions">
          <button type="button" @click="closeEditResultDialog">Cancel</button>
          <button type="button" @click="saveEditedResultRow" :disabled="editResultLoading">
            {{ editResultLoading ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>
      </div>
    </div>

    <section v-else-if="currentView === 'leader-boards'" class="json-loader-section mt-4 rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm">
      <div v-if="createLeaderBoardSuccessMessage" class="success success-banner" role="status">
        <span>{{ createLeaderBoardSuccessMessage }}</span>
        <button
          type="button"
          class="plain-button dismiss-button"
          @click="createLeaderBoardSuccessMessage = ''"
          aria-label="Dismiss success message"
        >&times;</button>
      </div>
      <p v-if="leaderBoardsErrorMessage" class="error">{{ leaderBoardsErrorMessage }}</p>
      <p v-if="leaderBoardsLoading">Loading leader boards...</p>

      <div class="leader-boards-layout">
        <div class="json-output-panel">
          <div class="panel-heading-row">
            <h3 class="panel-heading">Leader Boards</h3>
            <button
              type="button"
              class="help-icon-button"
              aria-label="Leader boards help"
              @click="showLeaderBoardHelpDialog = true"
            >?</button>
          </div>
          <table v-if="!leaderBoardsLoading" class="events-table my-4 w-full border-collapse overflow-hidden rounded-lg bg-white">
            <thead>
              <tr>
                <th>Name</th>
                <th>Year</th>
                <th>Events</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="leaderBoard in leaderBoards" :key="leaderBoard.id">
                <td>
                  <button type="button" class="link-button" @click="openLeaderBoardEventsDialog(leaderBoard)">
                    {{ leaderBoard.name }}
                  </button>
                </td>
                <td>{{ leaderBoard.year }}</td>
                <td>{{ leaderBoard.eventCount }}</td>
                <td class="action-cell whitespace-nowrap">
                  <button v-if="isLoggedIn" type="button" class="action-button mr-2 rounded-md border border-indigo-600 bg-indigo-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-indigo-700" @click="openEditLeaderBoardDialog(leaderBoard)">Edit</button>
                  <button type="button" class="action-button rounded-md border border-indigo-600 bg-indigo-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-indigo-700" @click="createLeaderBoardScoreView(leaderBoard)">View</button>
                </td>
              </tr>
              <tr v-if="leaderBoards.length === 0">
                <td colspan="4" class="empty-state">No leader boards yet.</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="activeLeaderBoard !== null" class="json-output-panel transformed-output-panel">
          <h3 class="panel-heading">{{ activeLeaderBoard.name }}</h3>
          <p v-if="leaderBoardScoresErrorMessage" class="error">{{ leaderBoardScoresErrorMessage }}</p>
          <p v-if="leaderBoardScoresLoading">Creating scores...</p>

          <div v-if="!leaderBoardScoresLoading && leaderBoardScoresRows.length > 0" class="transformed-mode-switch">
            <label>
              <input v-model="leaderBoardScoresShowRaw" type="checkbox" />
              Raw
            </label>
            <label>
              <input v-model="leaderBoardScoresShowRank" type="checkbox" />
              Rank
            </label>
          </div>

          <table v-if="!leaderBoardScoresLoading && leaderBoardScoresRows.length > 0" class="events-table transformed-table">
            <thead>
              <tr>
                <th
                  v-for="column in leaderBoardScoreColumns"
                  :key="`leader-board-score-header-${column}`"
                  :class="{ 'sortable-header': isLeaderBoardScoreColumn(column) }"
                  @click="sortLeaderBoardScoresBy(column)"
                >
                  {{ leaderBoardColumnLabel(column) }}{{ leaderBoardSortIndicator(column) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, rowIndex) in sortedLeaderBoardScoreRows" :key="`leader-board-score-row-${rowIndex}`">
                <td
                  v-for="column in leaderBoardScoreColumns"
                  :key="`leader-board-score-cell-${rowIndex}-${column}`"
                  :class="{
                    'scaled-score-cell': !leaderBoardScoresShowRaw && column !== 'team_name' && column !== 'team_member',
                    'member-cell': column === 'team_member'
                  }"
                  @click="column === 'team_member' ? openLeaderBoardMemberDialog(row) : null"
                >
                  {{ formatLeaderBoardScoreCell(row, column) }}
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else-if="!leaderBoardScoresLoading" class="empty-state">No scores found for this leader board.</p>
        </div>
      </div>
    </section>

    <div v-if="showLeaderBoardMemberDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Member event scores">
        <h3>Member Event Scores</h3>
        <p>{{ selectedLeaderBoardMember }}</p>
        <p v-if="leaderBoardMemberEventsErrorMessage" class="error">{{ leaderBoardMemberEventsErrorMessage }}</p>
        <p v-if="leaderBoardMemberEventsLoading">Loading event scores...</p>

        <table v-if="!leaderBoardMemberEventsLoading && leaderBoardMemberEventRows.length > 0" class="events-table mapping-table">
          <thead>
            <tr>
              <th>Event</th>
              <th>Date</th>
              <th>Score</th>
              <th>Categories</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="eventRow in leaderBoardMemberEventRows" :key="`member-event-row-${eventRow.eventId}`">
              <td>{{ eventRow.eventName }}</td>
              <td>{{ eventRow.date }}</td>
              <td>{{ eventRowScoreValue(eventRow) }}</td>
              <td>{{ eventRowCategoriesText(eventRow) || ' ' }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else-if="!leaderBoardMemberEventsLoading" class="empty-state">No event scores found for this member.</p>

        <div class="mapping-dialog-actions">
          <button type="button" @click="closeLeaderBoardMemberDialog">Close</button>
        </div>
      </div>
    </div>

    <div v-if="showLeaderBoardEventsDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Leader board events">
        <h3>{{ leaderBoardEventsTitle || 'Leader Board Events' }}</h3>
        <p v-if="leaderBoardEventsErrorMessage" class="error">{{ leaderBoardEventsErrorMessage }}</p>
        <p v-if="leaderBoardEventsLoading">Loading events...</p>

        <table v-if="!leaderBoardEventsLoading && leaderBoardEvents.length > 0" class="events-table mapping-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Series</th>
              <th>Date</th>
              <th>Organiser</th>
              <th class="text-right">Duration (hrs)</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="eventItem in leaderBoardEvents" :key="`leader-board-event-${eventItem.id}`">
              <td>{{ eventItem.name }}</td>
              <td>{{ eventItem.series }}</td>
              <td>{{ eventItem.date }}</td>
              <td>{{ eventItem.organiser }}</td>
              <td class="duration-cell">{{ formatDurationHours(eventItem.durationHours) }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else-if="!leaderBoardEventsLoading" class="empty-state">No events linked to this leader board.</p>

        <div class="mapping-dialog-actions">
          <button type="button" @click="closeLeaderBoardEventsDialog">Close</button>
        </div>
      </div>
    </div>

    <div v-if="showLeaderBoardHelpDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Leader board help">
        <h3>About Leader Boards</h3>
        <p>A Leader Board has the results for every event that is included in the board.</p>
        <p>The results are scaled so the competitor with the top score receives the maximum value and everyone else gets a proportional value.</p>
        <p>The maximum value depends on the event duration:</p>
        <ul class="help-list">
          <li><strong>24&nbsp;HR</strong> → 120</li>
          <li><strong>12&nbsp;HR</strong> → 100</li>
          <li><strong>6&nbsp;HR</strong> → 80</li>
          <li><strong>3&nbsp;HR</strong> → 60</li>
          <li><strong>2&nbsp;HR</strong> → 50</li>
          <li><strong>1&nbsp;HR</strong> → 30</li>
        </ul>

        <div class="mapping-dialog-actions">
          <button type="button" @click="showLeaderBoardHelpDialog = false">Close</button>
        </div>
      </div>
    </div>

    <div v-if="showCreateLeaderBoardDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Create leader board">
        <h3>Create Leader Board</h3>
        <div class="json-loader-controls">
          <label>
            Name
            <input v-model="newLeaderBoardName" type="text" placeholder="Leader board name" />
          </label>
          <label>
            Year
            <input v-model="newLeaderBoardYear" type="text" inputmode="numeric" placeholder="2026" />
          </label>
        </div>
        <p v-if="leaderBoardYearResultsLoading">Loading results for selected year...</p>
        <p v-if="leaderBoardYearResultsErrorMessage" class="error">{{ leaderBoardYearResultsErrorMessage }}</p>
        <p v-if="createLeaderBoardErrorMessage" class="error">{{ createLeaderBoardErrorMessage }}</p>

        <table v-if="leaderBoardYearResults.length > 0" class="events-table mapping-table">
          <thead>
            <tr>
              <th>Select</th>
              <th>Name</th>
              <th>Series</th>
              <th>Date</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="result in leaderBoardYearResults" :key="`leader-board-result-${result.id}`">
              <td>
                <input
                  type="checkbox"
                  :checked="selectedLeaderBoardResultIds.includes(result.id)"
                  @change="toggleLeaderBoardResultSelection(result.id)"
                />
              </td>
              <td>{{ result.name }}</td>
              <td>{{ result.series }}</td>
              <td>{{ result.date }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else-if="!leaderBoardYearResultsLoading" class="empty-state">Load year results to select entries.</p>

        <div class="mapping-dialog-actions">
          <button type="button" @click="closeCreateLeaderBoardDialog">Cancel</button>
          <button type="button" @click="createLeaderBoard" :disabled="createLeaderBoardLoading">
            {{ createLeaderBoardLoading ? 'Saving...' : 'Save Leader Board' }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="showEditLeaderBoardDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Edit leader board">
        <h3>Edit Leader Board</h3>
        <div class="json-loader-controls">
          <label>
            Name
            <input v-model="editLeaderBoardName" type="text" placeholder="Leader board name" />
          </label>
          <label>
            Year
            <input v-model="editLeaderBoardYear" type="text" inputmode="numeric" placeholder="2026" />
          </label>
        </div>
        <p v-if="editLeaderBoardLoadingDetails">Loading leader board details...</p>
        <p v-if="editLeaderBoardYearResultsLoading">Loading results for selected year...</p>
        <p v-if="editLeaderBoardYearResultsErrorMessage" class="error">{{ editLeaderBoardYearResultsErrorMessage }}</p>
        <p v-if="editLeaderBoardErrorMessage" class="error">{{ editLeaderBoardErrorMessage }}</p>

        <table v-if="editLeaderBoardYearResults.length > 0" class="events-table mapping-table">
          <thead>
            <tr>
              <th>Select</th>
              <th>Name</th>
              <th>Series</th>
              <th>Date</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="result in editLeaderBoardYearResults" :key="`edit-leader-board-result-${result.id}`">
              <td>
                <input
                  type="checkbox"
                  :checked="selectedEditLeaderBoardResultIds.includes(result.id)"
                  @change="toggleEditLeaderBoardResultSelection(result.id)"
                />
              </td>
              <td>{{ result.name }}</td>
              <td>{{ result.series }}</td>
              <td>{{ result.date }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else-if="!editLeaderBoardYearResultsLoading" class="empty-state">Load year results to select entries.</p>

        <div class="mapping-dialog-actions">
          <button type="button" @click="closeEditLeaderBoardDialog">Cancel</button>
          <button type="button" @click="updateLeaderBoard" :disabled="editLeaderBoardLoading || editLeaderBoardLoadingDetails">
            {{ editLeaderBoardLoading ? 'Saving...' : 'Save Changes' }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="showLoginDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Login">
        <h3>Login</h3>
        <div class="json-loader-controls">
          <label>
            Username
            <input v-model="loginUsernameInput" type="text" placeholder="Username" />
          </label>
          <label>
            Password
            <input v-model="loginPasswordInput" type="password" placeholder="Password" @keyup.enter="submitLogin" />
          </label>
        </div>
        <p v-if="loginErrorMessage" class="error">{{ loginErrorMessage }}</p>
        <div class="mapping-dialog-actions">
          <button type="button" @click="closeLoginDialog">Cancel</button>
          <button type="button" @click="submitLogin" :disabled="loginSubmitting">{{ loginSubmitting ? 'Logging in...' : 'Login' }}</button>
        </div>
      </div>
    </div>

    <div v-if="showCategoryMappingDialog" class="dialog-backdrop">
      <div class="mapping-dialog" role="dialog" aria-modal="true" aria-label="Category mapping">
        <h3>Category Mapping</h3>
        <p>Map raw categories to transformed categories before running transform.</p>

        <table class="events-table mapping-table">
          <thead>
            <tr>
              <th>Raw Category</th>
              <th>Mapped Category</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, rowIndex) in categoryMappingRows" :key="`mapping-row-${rowIndex}`">
              <td>{{ row.rawCategory }}</td>
              <td>
                <select v-model="row.mappedCategory">
                  <option value="">Unmapped</option>
                  <option v-for="category in fixedCategoryColumns" :key="`map-option-${rowIndex}-${category}`" :value="category">
                    {{ category }}
                  </option>
                </select>
              </td>
            </tr>
          </tbody>
        </table>

        <div class="mapping-dialog-actions">
          <p v-if="categoryMappingErrorMessage" class="error mapping-dialog-error">{{ categoryMappingErrorMessage }}</p>
          <button type="button" @click="closeCategoryMappingDialog">Cancel</button>
          <button type="button" @click="applyCategoryMappingAndTransform">Apply</button>
        </div>
      </div>
    </div>
  </main>
</template>

<style scoped>
main {
  @apply mx-auto my-8 max-w-[1680px] px-4 font-sans text-slate-800 lg:px-6;
}

.page-header {
  @apply rounded-xl border border-slate-200 bg-white px-5 py-4 shadow-sm;
}

h1 {
  @apply mb-1 text-3xl font-bold tracking-tight text-slate-900;
}

.page-subtitle {
  @apply m-0 text-sm text-slate-600;
}

h2 {
  @apply mb-2 text-xl font-semibold text-slate-900;
}

h3 {
  @apply mb-2 text-lg font-semibold text-slate-900;
}

input {
  @apply box-border w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm outline-none transition focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200;
}

select {
  @apply box-border w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm shadow-sm outline-none transition focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200;
}

button {
  @apply cursor-pointer rounded-md border border-indigo-600 bg-indigo-600 px-3 py-2 text-sm font-medium text-white shadow-sm transition hover:border-indigo-700 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-300 disabled:cursor-not-allowed disabled:border-slate-300 disabled:bg-slate-200 disabled:text-slate-500;
}

button.plain-button {
  @apply border-0 bg-transparent px-1 py-0 text-base font-semibold text-slate-500 shadow-none hover:bg-transparent hover:text-slate-700 focus:outline-none focus:ring-0;
}

.link-button {
  @apply cursor-pointer border-0 bg-transparent p-0 text-left font-medium text-indigo-700 underline decoration-indigo-300 underline-offset-2 transition hover:text-indigo-900 hover:decoration-indigo-400 focus:outline-none focus:ring-0 rounded-none shadow-none hover:bg-transparent focus:bg-transparent active:bg-transparent;
}

.view-switcher {
  @apply inline-flex items-center gap-2;
}

.tab-button {
  @apply border-transparent bg-transparent text-slate-700 shadow-none hover:bg-slate-100;
}

.view-switcher .active {
  @apply border-indigo-200 bg-white font-semibold text-indigo-700 shadow-sm;
}

.action-row {
  @apply mb-2 mt-3 flex flex-wrap items-center gap-2;
}

.panel-heading {
  @apply text-xl font-semibold text-slate-900;
}

.panel-heading-row {
  @apply mb-2 flex items-center gap-2;
}

.help-icon-button {
  @apply inline-flex h-6 w-6 items-center justify-center rounded-full border border-indigo-200 bg-indigo-50 px-0 py-0 text-xs font-semibold text-indigo-700 shadow-none hover:border-indigo-300 hover:bg-indigo-100 focus:outline-none focus:ring-0;
}

.action-cell {
  @apply whitespace-nowrap;
}

.action-button {
  @apply mr-1 px-2 py-1 text-[11px] leading-4;
}

.action-button:last-child {
  @apply mr-0;
}

.danger-button {
  @apply border-red-600 bg-red-600 hover:border-red-700 hover:bg-red-700 focus:ring-red-300;
}

.events-table {
  @apply my-2 w-full border-collapse overflow-hidden rounded-md bg-white;
}

.events-table th,
.events-table td {
  @apply border border-slate-200 px-2 py-1 text-left text-xs leading-4;
}

.events-table th {
  @apply sticky top-0 bg-slate-100 font-semibold uppercase tracking-wide text-slate-600;
}

.events-table tbody tr:nth-child(even) {
  @apply bg-slate-50/60;
}

.events-table tbody tr:hover {
  @apply bg-indigo-50/40;
}

.events-table th.sortable-header {
  @apply cursor-pointer select-none;
}

.error {
  @apply my-2 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700;
}

.success {
  @apply my-2 rounded-md border border-green-200 bg-green-50 px-3 py-2 text-sm text-green-700;
}

.success-banner {
  @apply flex items-center justify-between gap-3;
}

.dismiss-button {
  @apply leading-none;
}

.duration-cell {
  @apply text-right font-mono text-sm;
}

.empty-state {
  @apply rounded-md border border-dashed border-slate-300 bg-slate-50 px-4 py-6 text-center text-slate-600;
}

.json-loader-section {
  @apply mt-4 rounded-xl border border-slate-200 bg-white p-4 text-left shadow-sm;
}

.json-loader-subtitle {
  @apply mt-0 text-sm text-slate-600;
}

.json-loader-controls {
  @apply my-2 mb-4 grid gap-3;
  grid-template-columns: repeat(auto-fit, minmax(220px, 280px));
}

.json-loader-controls label {
  @apply flex flex-col gap-1 text-sm font-medium text-slate-700;
}

.json-loader-url {
  @apply my-2 rounded bg-slate-100 px-2 py-1 break-all text-xs text-slate-600;
}

.transformed-mode-switch {
  @apply mb-2 flex flex-wrap items-center gap-4 rounded-md bg-slate-50 px-3 py-2;
}

.transformed-mode-switch label {
  @apply inline-flex items-center gap-1 text-sm font-medium text-slate-700;
}

.events-table td.scaled-score-cell {
  @apply text-right;
}

.events-table td.member-cell {
  @apply cursor-pointer font-medium text-indigo-700 underline decoration-indigo-300 underline-offset-2;
}

.events-table td.result-member-warning {
  @apply font-semibold text-red-700;
}

.dialog-backdrop {
  @apply fixed inset-0 z-[1000] flex items-center justify-center bg-slate-900/45 p-4 backdrop-blur-[1px];
}

.mapping-dialog {
  @apply max-h-[90vh] overflow-auto rounded-xl border border-slate-200 bg-white p-5 text-slate-900 shadow-xl;
  width: min(760px, 100%);
}

.mapping-table {
  @apply my-2;
}

.mapping-dialog-actions {
  @apply flex items-center justify-end gap-2;
}

.mapping-dialog-error {
  @apply mr-auto border-none bg-transparent p-0;
}

.help-list {
  @apply mb-4 list-disc pl-6 text-sm text-slate-700;
}

.json-output-panel {
  @apply mt-4 min-w-0 rounded-lg border border-slate-200 bg-white p-4 shadow-sm;
}

.json-output-panel h3 {
  @apply mt-0;
}

.json-panels {
  @apply grid w-full items-start gap-4;
  grid-template-columns: 1fr;
}

.leader-boards-layout {
  @apply grid w-full items-start gap-4;
  grid-template-columns: minmax(0, 0.33fr) minmax(0, 0.67fr);
}

.transformed-table {
  @apply mt-0;
  width: max-content;
}

.transformed-output-panel {
  @apply w-full min-w-0 overflow-x-auto;
}

@media (min-width: 1024px) {
  .json-panels {
    grid-template-columns: minmax(0, 1fr) minmax(0, 2fr);
  }

  .leader-boards-layout {
    grid-template-columns: minmax(300px, 0.33fr) minmax(0, 0.67fr);
  }
}
</style>
