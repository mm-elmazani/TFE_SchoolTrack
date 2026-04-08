import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import { DeleteClassDialog } from '../components/DeleteClassDialog';
import { classApi } from '../api/classApi';

vi.mock('../api/classApi', () => ({
  classApi: { delete: vi.fn(), getAll: vi.fn() },
}));

const mockClass = {
  id: 'c1', name: '5ème A', year: '2025-2026', nb_students: 25, nb_teachers: 2,
  created_at: '', updated_at: '',
};

beforeEach(() => vi.clearAllMocks());

describe('DeleteClassDialog', () => {
  it('renders dialog when open with class data', () => {
    render(<DeleteClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText('Supprimer la classe')).toBeInTheDocument();
  });

  it('shows class name in confirmation text', () => {
    render(<DeleteClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/5.me A/)).toBeInTheDocument();
  });

  it('renders delete and cancel buttons', () => {
    render(<DeleteClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByRole('button', { name: /Supprimer/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Annuler/i })).toBeInTheDocument();
  });

  it('warns that action is irreversible', () => {
    render(<DeleteClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    expect(screen.getByText(/irr.versible/i)).toBeInTheDocument();
  });

  it('closes when cancel is clicked', () => {
    const onOpenChange = vi.fn();
    render(<DeleteClassDialog cls={mockClass} open={true} onOpenChange={onOpenChange} />);
    fireEvent.click(screen.getByRole('button', { name: /Annuler/i }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it('calls classApi.delete when delete button clicked', async () => {
    vi.mocked(classApi.delete).mockResolvedValue({} as any);
    render(<DeleteClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /Supprimer définitivement/i }));
    await waitFor(() => expect(classApi.delete).toHaveBeenCalledWith('c1'));
  });

  it('shows server error on delete failure', async () => {
    vi.mocked(classApi.delete).mockRejectedValue({
      response: { data: { detail: 'Impossible de supprimer: élèves liés' } },
    });
    render(<DeleteClassDialog cls={mockClass} open={true} onOpenChange={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: /Supprimer définitivement/i }));
    expect(await screen.findByText('Impossible de supprimer: élèves liés')).toBeInTheDocument();
  });

  it('does not render when closed', () => {
    render(<DeleteClassDialog cls={mockClass} open={false} onOpenChange={vi.fn()} />);
    expect(screen.queryByText('Supprimer la classe')).not.toBeInTheDocument();
  });
});
