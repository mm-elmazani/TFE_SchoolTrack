import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { UpdateClassDialog } from '../components/UpdateClassDialog';
import { classApi } from '../api/classApi';

vi.mock('../api/classApi', () => ({
  classApi: { update: vi.fn(), getAll: vi.fn(), delete: vi.fn() },
}));

const mockClass = {
  id: 'c1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2,
  created_at: '', updated_at: '',
};

beforeEach(() => vi.clearAllMocks());

describe('UpdateClassDialog', () => {
  it('renders dialog when open with class data', () => {
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Modifier la classe')).toBeInTheDocument();
  });

  it('pre-fills class name', () => {
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByDisplayValue('5ème A')).toBeInTheDocument();
  });

  it('pre-fills school year', () => {
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByDisplayValue('2025-2026')).toBeInTheDocument();
  });

  it('renders form labels', () => {
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/Nom de la classe/i)).toBeInTheDocument();
    expect(screen.getAllByText(/Ann.e scolaire/i).length).toBeGreaterThan(0);
  });

  it('renders save and cancel buttons', () => {
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /sauvegarder/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /annuler/i })).toBeInTheDocument();
  });

  it('renders dialog subtitle', () => {
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/nom ou l.ann.e/i)).toBeInTheDocument();
  });

  it('calls classApi.update on submit', async () => {
    vi.mocked(classApi.update).mockResolvedValue({ id: 'c1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2, created_at: '', updated_at: '' });
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    await waitFor(() => expect(classApi.update).toHaveBeenCalled());
  });

  it('shows server error on update failure', async () => {
    vi.mocked(classApi.update).mockRejectedValue({
      response: { data: { detail: 'Nom déjà utilisé' } },
    });
    render(<UpdateClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /sauvegarder/i }));
    expect(await screen.findByText('Nom déjà utilisé')).toBeInTheDocument();
  });
});
