import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image("GlendaImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 200)

                Text("9p4i")
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundColor(.black)

                Text("Plan 9 File Browser")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.gray)

                Spacer()

                Text("Powered by Glenda")
                    .font(.system(size: 12, weight: .light, design: .rounded))
                    .foregroundColor(.gray)
                    .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
