import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import CheckpointTimelineScreen from '../screens/CheckpointTimelineScreen';
import { tripApi } from '../api/tripApi';

vi.mock('../api/tripApi', () => ({
  tripApi: { getCheckpointsSummary: vi.fn() },
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ id: 'trip-1', schoolSlug: 'dev' }), useNavigate: () => vi.fn() };
});

describe('CheckpointTimelineScreen', () => {
  it('renders empty state', async () => {
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue({
      trip_id: 'trip-1',
      trip_destination: 'Bruges',
      total_checkpoints: 0,
      active_checkpoints: 0,
      closed_checkpoints: 0,
      total_scans: 0,
      avg_duration_minutes: null,
      timeline: [],
    } as any);
    render(<CheckpointTimelineScreen />);
    expect(await screen.findByText(/Aucun checkpoint/i)).toBeInTheDocument();
  });

  it('renders checkpoint data', async () => {
    vi.mocked(tripApi.getCheckpointsSummary).mockResolvedValue({
      trip_id: 'trip-1',
      trip_destination: 'Bruges',
      total_checkpoints: 1,
      active_checkpoints: 0,
      closed_checkpoints: 1,
      total_scans: 10,
      avg_duration_minutes: 15,
      timeline: [{
        id: 'cp-1', name: 'Depart', description: null, sequence_order: 1,
        status: 'CLOSED', created_at: null, started_at: null, closed_at: null,
        created_by_name: 'M. Dupont', scan_count: 10, student_count: 20,
        duration_minutes: 15,
      }],
    } as any);
    render(<CheckpointTimelineScreen />);
    expect(await screen.findByText(/Depart/)).toBeInTheDocument();
  });
});
