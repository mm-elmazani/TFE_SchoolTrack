import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import { UpdateTripDialog } from '../components/UpdateTripDialog';
import { tripApi } from '../api/tripApi';
import { classApi } from '@/features/classes/api/classApi';

vi.mock('../api/tripApi', () => ({
  tripApi: { update: vi.fn(), getAll: vi.fn() },
}));

vi.mock('@/features/classes/api/classApi', () => ({
  classApi: { getAll: vi.fn() },
}));

const mockTrip = {
  id: 't1', destination: 'Paris', date: '2026-05-10', description: 'Voyage culturel',
  status: 'PLANNED', total_students: 25, classes: ['5ème A'], created_at: '', updated_at: '',
} as any;

const mockClasses = [
  { id: 'c1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2, created_at: '', updated_at: '' },
  { id: 'c2', name: '6ème B', year: '2025-2026', nb_students: 20, nb_teachers: 1, created_at: '', updated_at: '' },
];

beforeEach(() => vi.clearAllMocks());

describe('UpdateTripDialog', () => {
  it('renders dialog when open with trip data', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Modifier le voyage')).toBeInTheDocument();
  });

  it('pre-fills destination field', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    // useEffect resets form — wait for destination input to appear
    expect(await screen.findByDisplayValue('Paris')).toBeInTheDocument();
  });

  it('renders form fields', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Destination')).toBeInTheDocument();
    expect(screen.getByText('Date')).toBeInTheDocument();
    expect(screen.getByText('Description')).toBeInTheDocument();
  });

  it('renders save and cancel buttons', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /sauvegarder/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /annuler/i })).toBeInTheDocument();
  });

  it('renders class list when loaded', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getByText('6ème B')).toBeInTheDocument();
  });

  it('renders classes participantes label', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Classes participantes/i)).toBeInTheDocument();
  });

  it('renders status field', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Statut')).toBeInTheDocument();
  });

  it('renders dialog subtitle', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<UpdateTripDialog trip={mockTrip} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/informations.*statut/i)).toBeInTheDocument();
  });
});
