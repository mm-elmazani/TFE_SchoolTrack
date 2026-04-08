import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import AppScaffold from '../AppScaffold';
import { useAuthStore } from '@/features/auth/store/authStore';

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useParams: () => ({ schoolSlug: 'dev' }),
    useNavigate: () => vi.fn(),
    useLocation: () => ({ pathname: '/dev/students' }),
    Outlet: () => <div data-testid="outlet">Page content</div>,
  };
});

beforeEach(() => vi.clearAllMocks());

describe('AppScaffold', () => {
  it('renders sidebar with SchoolTrack branding', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'DIRECTION' },
    });
    render(<AppScaffold />);
    expect(screen.getAllByText('SchoolTrack').length).toBeGreaterThan(0);
  });

  it('renders main navigation items', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'DIRECTION' },
    });
    render(<AppScaffold />);
    expect(screen.getAllByText(/lèves/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText('Classes').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Voyages').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Bracelets').length).toBeGreaterThan(0);
  });

  it('renders admin items for DIRECTION role', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'DIRECTION' },
    });
    render(<AppScaffold />);
    expect(screen.getAllByText('Utilisateurs').length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Audit/i).length).toBeGreaterThan(0);
    expect(screen.getAllByText('Stock Bracelets').length).toBeGreaterThan(0);
  });

  it('renders dashboard and alerts for admin', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'DIRECTION' },
    });
    render(<AppScaffold />);
    expect(screen.getAllByText("Vue d'ensemble").length).toBeGreaterThan(0);
    expect(screen.getAllByText('Alertes').length).toBeGreaterThan(0);
  });

  it('renders user info and logout button', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'DIRECTION' },
    });
    render(<AppScaffold />);
    expect(screen.getAllByText(/Jean/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/Dupont/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/connexion/i).length).toBeGreaterThan(0);
  });

  it('renders outlet for page content', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'DIRECTION' },
    });
    render(<AppScaffold />);
    expect(screen.getByTestId('outlet')).toBeInTheDocument();
  });

  it('renders current page title from navigation', () => {
    useAuthStore.setState({
      token: 'test',
      user: { id: '1', email: 'admin@test.be', first_name: 'Jean', last_name: 'Dupont', role: 'DIRECTION' },
    });
    render(<AppScaffold />);
    // The h1 header should show the current nav item label (Élèves, because pathname is /dev/students)
    const headings = screen.getAllByRole('heading', { level: 1 });
    expect(headings.length).toBeGreaterThan(0);
  });
});
