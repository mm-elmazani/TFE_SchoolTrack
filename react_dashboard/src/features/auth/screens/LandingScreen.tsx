import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { GraduationCap } from 'lucide-react';

export default function LandingScreen() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-schooltrack-neutral p-4">
      <Card className="w-full max-w-[420px] shadow-md border-slate-200 overflow-hidden rounded-2xl">
        <div className="h-1.5 bg-schooltrack-primary w-full" />
        <CardHeader className="space-y-1 pb-6 pt-8 items-center text-center">
          <GraduationCap className="h-12 w-12 text-schooltrack-primary mb-2" />
          <CardTitle className="text-2xl font-bold tracking-tight text-schooltrack-primary">SchoolTrack</CardTitle>
        </CardHeader>
        <CardContent className="text-center space-y-4">
          <p className="text-slate-600 text-sm">
            Accedez au dashboard de votre etablissement via l'URL fournie par votre direction.
          </p>
          <p className="text-slate-400 text-xs">
            Exemple : <code className="bg-slate-100 px-2 py-1 rounded text-xs">dashboard.schooltrack.yourschool.be/<strong>votre-ecole</strong>/login</code>
          </p>
          <div className="mt-10 pt-6 border-t border-slate-100">
            <p className="text-[10px] text-slate-400 uppercase tracking-widest font-medium">
              SchoolTrack &copy; 2026 - EPHEC
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
