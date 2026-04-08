import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { CreateTripDialog } from '../components/CreateTripDialog';
import { classApi } from '@/features/classes/api/classApi';
import { tripApi } from '../api/tripApi';

vi.mock('@/features/classes/api/classApi', () => ({
  classApi: { getAll: vi.fn() },
}));

vi.mock('../api/tripApi', () => ({
  tripApi: { create: vi.fn() },
}));

const mockClasses = [
  { id: 'c1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2, created_at: '', updated_at: '' },
  { id: 'c2', name: '6ème B', year: '2025-2026', nb_students: 20, nb_teachers: 1, created_at: '', updated_at: '' },
];

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(classApi.getAll).mockResolvedValue([]);
});

describe('CreateTripDialog', () => {
  it('renders dialog when open', () => {
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('heading', { name: /voyage/i })).toBeInTheDocument();
  });

  it('renders dialog title', () => {
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Créer un voyage')).toBeInTheDocument();
  });

  it('renders dialog subtitle', () => {
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Planifiez une nouvelle sortie/i)).toBeInTheDocument();
  });

  it('renders destination and date fields', () => {
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Destination')).toBeInTheDocument();
    expect(screen.getByText('Date')).toBeInTheDocument();
  });

  it('renders description field', () => {
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Description \(optionnelle\)/i)).toBeInTheDocument();
  });

  it('renders classes participantes label', () => {
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Classes participantes')).toBeInTheDocument();
  });

  it('renders class list when loaded', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(await screen.findByText('5ème A')).toBeInTheDocument();
    expect(screen.getByText('6ème B')).toBeInTheDocument();
  });

  it('renders create and cancel buttons', () => {
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /Créer le voyage/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Annuler/i })).toBeInTheDocument();
  });

  it('closes on cancel button click', () => {
    const onOpenChange = vi.fn();
    render(<CreateTripDialog open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /Annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('shows server error on API failure', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    vi.mocked(tripApi.create).mockRejectedValue({
      response: { data: { detail: 'Voyage déjà planifié à cette date' } },
    });
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    await screen.findByText('5ème A');
    fireEvent.change(screen.getByPlaceholderText(/ex: Rome/i), { target: { value: 'Paris' } });
    // Set date
    const dateInput = document.querySelector('input[type="date"]') as HTMLInputElement;
    if (dateInput) fireEvent.change(dateInput, { target: { value: '2026-05-10' } });
    // Select a class
    fireEvent.click(screen.getByText('5ème A'));
    fireEvent.click(screen.getByRole('button', { name: /Créer le voyage/i }));
    expect(await screen.findByText('Voyage déjà planifié à cette date')).toBeInTheDocument();
  });

  it('calls classApi.create on submit when class selected', async () => {
    vi.mocked(classApi.getAll).mockResolvedValue(mockClasses);
    vi.mocked(tripApi.create).mockResolvedValue({ id: 't1' } as any);
    render(<CreateTripDialog open={true} onOpenChange={vi.fn()} />);
    await screen.findByText('5ème A');
    fireEvent.change(screen.getByPlaceholderText(/ex: Rome/i), { target: { value: 'Paris' } });
    const dateInput = document.querySelector('input[type="date"]') as HTMLInputElement;
    if (dateInput) fireEvent.change(dateInput, { target: { value: '2026-05-10' } });
    fireEvent.click(screen.getByText('5ème A'));
    fireEvent.click(screen.getByRole('button', { name: /Créer le voyage/i }));
    await waitFor(() => expect(tripApi.create).toHaveBeenCalled());
  });

  it('does not render when closed', () => {
    render(<CreateTripDialog open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText('Créer un voyage')).not.toBeInTheDocument();
  });
});
